using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using Key = CrestCore.Application.StoredSessionCodec.Key;

namespace CrestCore.Application;

/// Owns the native app's durable session as typed records. Native views propose
/// value deltas; only an accepted revision becomes visible. Published documents
/// are immutable, so storage can serialize an older checkpoint on its worker while
/// the UI continues editing the current revision. The session holds browsing data
/// only: which Space and tab a window shows is window state, so selection fields in
/// an older document are dropped here and never written. Commands read what the
/// window shows as context and answer with a hint.
public sealed partial class NativeSessionAuthority {
    #region Variables

    public const int MaximumBytes = 64 * 1024 * 1024;
    /// The largest edit request or answer the session exchanges with a window.
    public const int MaximumEditBytes = 4 * 1024 * 1024;
    internal static readonly object Gate = new();
    private const string WorkspaceKindField = "coreWorkspaceKind";
    private const string PrivateBrowsingField = "corePrivateBrowsing";
    private SessionDocument document;
    private NativeSessionReplacement? replacement;
    private readonly BrowserWorkspaceKind workspaceKind;
    private readonly bool privateBrowsing;
    public ulong Revision { get; private set; } = 1;
    public Adapter? Engine { get; private set; }

    #endregion

    #region Constructors

    public NativeSessionAuthority(ReadOnlySpan<byte> bytes) {
        var input = Parse(bytes);
        workspaceKind = input[WorkspaceKindField]?.GetValue<string>() switch {
            null or "persistent" => BrowserWorkspaceKind.Persistent,
            "private" => BrowserWorkspaceKind.Private,
            "temporary" => throw new BrowserRuleException(BrowserRuleCodes.BorrowedSourceRequired),
            _ => throw new BrowserRuleException(BrowserRuleCodes.InvalidWorkspaceKind)
        };
        privateBrowsing = input[PrivateBrowsingField]?.GetValue<bool>() ?? workspaceKind == BrowserWorkspaceKind.Private;
        document = StoredSessionCodec.DecodeSession(StoredSessionCodec.Fields(input, [WorkspaceKindField, PrivateBrowsingField]));
        Validate(document);
    }

    #endregion

    #region Actions - Engine registration

    /// Process-local registration shares the transport descriptor contract. It
    /// cannot be changed by session edits, restored files or remote sync records.
    public void RegisterEngine(ReadOnlySpan<byte> descriptor) {
        var engine = Protocol.Descriptor(descriptor);
        if (engine.Role != AdapterRoles.Engine || !EngineCapabilities.Required.All(engine.Supports))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidEngineRegistration);
        lock (Gate) {
            if (Engine is not null) throw new BrowserRuleException(BrowserRuleCodes.EngineAlreadyRegistered);
            Engine = engine;
        }
    }

    #endregion

    #region Actions - Document validation

    private static JsonObject Parse(ReadOnlySpan<byte> bytes) {
        if (bytes.Length == 0 || bytes.Length > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionSizeLimit);
        return JsonNode.Parse(bytes, documentOptions: new() { MaxDepth = 64 })!.AsObject();
    }

    internal static Guid Id(JsonNode? value) {
        if (value is JsonObject obj) value = obj[Key.RawValue];
        var id = Guid.Parse(value!.GetValue<string>());
        if (id == Guid.Empty) throw new BrowserRuleException(BrowserRuleCodes.InvalidIdentity);
        return id;
    }

    private static void Validate(SessionDocument value) {
        var spaces = value.Spaces;
        var ids = new HashSet<Guid>(); var tabs = new HashSet<Guid>(); var profiles = new HashSet<Guid>();
        foreach (var space in spaces) {
            if (space.Id == Guid.Empty || space.ProfileId == Guid.Empty || space.Tabs.Any(tab => tab.Id == Guid.Empty))
                throw new BrowserRuleException(BrowserRuleCodes.InvalidIdentity);
            if (!ids.Add(space.Id)) throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpace);
            // A Space is exactly one profile and a profile belongs to exactly one
            // Space. Two Spaces sharing a profile would share cookies, credentials
            // and extension access across an isolation boundary the user relies on,
            // and would make "which Space owns this profile" unanswerable.
            if (!profiles.Add(space.ProfileId)) throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpaceProfile);
            foreach (var tab in space.Tabs)
                if (!tabs.Add(tab.Id)) throw new BrowserRuleException(BrowserRuleCodes.DuplicateTab);
        }
        var pendingIds = new HashSet<Guid>();
        foreach (var deletion in Deletions(value.Metadata)) {
            var id = Id(deletion!["spaceID"]);
            var profile = Id(deletion["profileID"]);
            _ = Id(deletion["operationID"]);
            if (!pendingIds.Add(id) || !spaces.Any(s => s.Id == id && s.ProfileId == profile))
                throw new BrowserRuleException(BrowserRuleCodes.InvalidDeletionIntent);
        }
        // An empty temporary workspace and a briefly stale window selection are
        // valid native states. Window reconciliation handles their presentation.
    }

    /// A Space's settings without its records, as settings commands answer them.
    /// Split metadata stays: windows read it with the settings.
    private static SpaceDocument Settings(SpaceDocument space) => space with { Tabs = [], Folders = [], ArchivedTabs = [], History = [] };

    private static SessionDocument Replacing(SessionDocument session, params SpaceDocument[] edited) => session with {
        Spaces = session.Spaces.Select(space => edited.FirstOrDefault(value => value.Id == space.Id) ?? space).ToArray()
    };

    #endregion

    #region Actions - Session revisions

    private SessionDocument Prepare(ulong expected, ReadOnlySpan<byte> bytes, JsonNode? authorizedDeletions = null,
        bool nativeValueEdit = false) {
        RequireWritable();
        if (expected != Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
        var delta = Parse(bytes);
        if (delta["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
        var metadata = delta["metadata"] is JsonObject suppliedMetadata
            ? KeepingPreferences(StoredSessionCodec.Fields(suppliedMetadata, [Key.Spaces, LegacySelectionFields.SelectedSpace]))
            : document.Metadata;
        if (!EqualDeletionIntents(metadata["spaceDeletions"], authorizedDeletions ?? document.Metadata["spaceDeletions"]))
            throw new BrowserRuleException(BrowserRuleCodes.DeletionRequiresCommand);
        var byId = document.Spaces.ToDictionary(s => s.Id);
        var proposed = new List<Guid>();
        foreach (var node in delta["spaces"]!.AsArray()) {
            var change = node!.AsObject(); var id = Id(change["id"]);
            proposed.Add(id);
            byId.TryGetValue(id, out var original);
            var supplied = change["metadata"] is JsonObject fields ? StoredSessionCodec.DecodeSpace(fields) : null;
            if ((supplied ?? original) is not { } settings || settings.Id != id)
                throw new BrowserRuleException(BrowserRuleCodes.WrongSpaceIdentity);
            byId[id] = new(settings.Metadata,
                Edited(original?.Tabs, change[Key.Tabs], StoredSessionCodec.DecodeTab, tab => tab.Id),
                Edited(original?.Folders, change[Key.Folders], StoredSessionCodec.DecodeFolder, folder => folder.Id),
                supplied?.SplitGroups ?? original!.SplitGroups,
                Edited(original?.ArchivedTabs, change[Key.ArchivedTabs], StoredSessionCodec.DecodeArchivedTab, archived => archived.Tab.Id),
                Edited(original?.History, change[Key.History], StoredSessionCodec.DecodeHistoryEntry, entry => entry.Id));
        }
        var spaceOrder = delta["spaceOrder"] is JsonArray suppliedOrder
            ? suppliedOrder.Select(Id).ToArray() : document.Spaces.Select(s => s.Id).ToArray();
        if (spaceOrder.Distinct().Count() != spaceOrder.Length || spaceOrder.Any(id => !byId.ContainsKey(id)))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidSpaceOrder);
        var next = new SessionDocument(metadata, spaceOrder.Select(id => byId[id]).ToArray());
        foreach (var existing in Deletions(document.Metadata))
            if (!Deletions(metadata).Any(d => SameDeletionIntent(d!, existing!)))
                throw new BrowserRuleException(BrowserRuleCodes.DeletionRequiresCommand);
        foreach (var deletion in Deletions(metadata)) {
            var id = Id(deletion!["spaceID"]);
            var original = document.Spaces.Single(s => s.Id == id);
            var retained = next.Spaces.SingleOrDefault(s => s.Id == id);
            if (retained is null || !original.Matches(retained))
                throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
        }
        Validate(next);
        ValidateBorrowedDocument(next);
        if (nativeValueEdit) RequireAccessibleValueEdit(next, proposed);
        return next;
    }

    /// One record collection after a delta's edit: a whole replacement, or
    /// removals and upserts by identity in the order it names, else the
    /// collection's own order.
    private static IReadOnlyList<T> Edited<T>(IReadOnlyList<T>? original, JsonNode? edit, Func<JsonNode?, T> decode,
        Func<T, Guid> identity) {
        var previous = original ?? [];
        if (edit is not JsonObject edits) return previous;
        if (edits["replace"] is JsonArray replacement) return replacement.Select(decode).ToArray();
        var records = previous.ToDictionary(identity);
        foreach (var removed in edits["remove"]!.AsArray()) records.Remove(Id(removed));
        foreach (var item in edits["upsert"]!.AsArray()) { var record = decode(item); records[identity(record)] = record; }
        var order = edits["order"] is JsonArray supplied ? supplied.Select(Id).ToArray() : previous.Select(identity).ToArray();
        if (order.Length != records.Count || order.Distinct().Count() != order.Length || order.Any(id => !records.ContainsKey(id)))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidRecordOrder);
        return order.Select(id => records[id]).ToArray();
    }

    private void RequireWritable(bool requireCurrentBorrowedPolicy = true) {
        if (released) throw new BrowserRuleException(BrowserRuleCodes.SessionReleased);
        if (replacement is not null) throw new BrowserRuleException(BrowserRuleCodes.SessionTransactionInProgress);
        if (borrowedSource is not null) {
            _ = RequireBorrowedSource();
            if (requireCurrentBorrowedPolicy) RequireBorrowedRevision(borrowedSourceRevision);
        }
    }

    /// `nativeValueEdit` marks a proposal that originates in the native views
    /// rather than in sync materialization, so it answers to the Space access
    /// gate exactly as a semantic command does.
    public ulong Commit(ulong expected, ReadOnlySpan<byte> delta, bool nativeValueEdit = false) {
        lock (Gate) {
            var next = Prepare(expected, delta, nativeValueEdit: nativeValueEdit);
            var revision = checked(Revision + 1);
            document = next; Revision = revision; return revision;
        }
    }

    public static (ulong Source, ulong Destination) CommitPair(
        NativeSessionAuthority source, ulong sourceRevision, ReadOnlySpan<byte> sourceDelta,
        NativeSessionAuthority destination, ulong destinationRevision, ReadOnlySpan<byte> destinationDelta) {
        if (ReferenceEquals(source, destination)) throw new BrowserRuleException(BrowserRuleCodes.SameSessionTransfer);
        lock (Gate) {
            var a = source.Prepare(sourceRevision, sourceDelta);
            var b = destination.Prepare(destinationRevision, destinationDelta);
            var ar = checked(source.Revision + 1); var br = checked(destination.Revision + 1);
            source.document = a; destination.document = b;
            source.Revision = ar; destination.Revision = br;
            return (ar, br);
        }
    }

    public NativeSessionCheckpoint Checkpoint(ulong expected) {
        lock (Gate) {
            if (expected != Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
            return new(document);
        }
    }

    #endregion
}
