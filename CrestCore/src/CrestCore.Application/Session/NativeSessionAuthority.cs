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
/// an older session are dropped here and never written. Commands read what the
/// window shows as context and answer with a hint.
public sealed partial class NativeSessionAuthority {
    #region Variables

    public const int MaximumBytes = 64 * 1024 * 1024;
    /// The largest edit request or answer the session exchanges with a window.
    public const int MaximumEditBytes = 4 * 1024 * 1024;
    internal static readonly object Gate = new();
    private const string WorkspaceKindField = "coreWorkspaceKind";
    private const string PrivateBrowsingField = "corePrivateBrowsing";
    private SessionState session;
    private NativeSessionReplacement? replacement;
    private readonly BrowserWorkspaceKind workspaceKind;
    private readonly bool privateBrowsing;
    /// The file a persistent session the core loaded keeps; null in memory.
    private readonly SessionStorage? storage;
    public ulong Revision { get; private set; } = 1;

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
        session = StoredSessionCodec.DecodeSession(input);
        Validate(session);
    }

    /// The persistent session the core loaded from `storage` and repaired.
    /// Every revision it accepts is saved there.
    internal NativeSessionAuthority(SessionState stored, SessionStorage storage) {
        workspaceKind = BrowserWorkspaceKind.Persistent;
        session = stored;
        Validate(session);
        this.storage = storage;
        storage.Enqueue(session, Revision);
    }

    #endregion

    #region Actions - Session validation

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

    private static void Validate(SessionState value) {
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
        foreach (var deletion in value.SpaceDeletions) {
            if (deletion.Id == Guid.Empty || deletion.SpaceId == Guid.Empty || deletion.ProfileId == Guid.Empty)
                throw new BrowserRuleException(BrowserRuleCodes.InvalidIdentity);
            if (!pendingIds.Add(deletion.SpaceId) || !spaces.Any(s => s.Id == deletion.SpaceId && s.ProfileId == deletion.ProfileId))
                throw new BrowserRuleException(BrowserRuleCodes.InvalidDeletionIntent);
        }
        // An empty temporary workspace and a briefly stale window selection are
        // valid native states. Window reconciliation handles their presentation.
    }

    /// A Space's settings without its records, as settings commands answer them.
    /// Split metadata stays: windows read it with the settings.
    private static SpaceState Settings(SpaceState space) => space with { Tabs = [], Folders = [], ArchivedTabs = [], History = [] };

    private static SessionState Replacing(SessionState session, params SpaceState[] edited) => session with {
        Spaces = session.Spaces.Select(space => edited.FirstOrDefault(value => value.Id == space.Id) ?? space).ToArray()
    };

    #endregion

    #region Actions - Session revisions

    private SessionState Prepare(ulong expected, ReadOnlySpan<byte> bytes, IReadOnlyList<SpaceDeletionState>? authorizedDeletions = null,
        bool nativeValueEdit = false) {
        RequireWritable();
        if (expected != Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
        var delta = Parse(bytes);
        if (delta["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
        // Only the preference commands change the app preferences, so a value
        // edit or a sync replacement keeps the owned ones.
        var settings = delta["metadata"] is JsonObject suppliedSettings
            ? StoredSessionCodec.DecodeSessionSettings(suppliedSettings) with { AppPreferences = session.AppPreferences }
            : session;
        if (!SameDeletions(settings.SpaceDeletions, authorizedDeletions ?? session.SpaceDeletions))
            throw new BrowserRuleException(BrowserRuleCodes.DeletionRequiresCommand);
        var byId = session.Spaces.ToDictionary(s => s.Id);
        var proposed = new List<Guid>();
        foreach (var node in delta["spaces"]!.AsArray()) {
            var change = node!.AsObject(); var id = Id(change["id"]);
            proposed.Add(id);
            byId.TryGetValue(id, out var original);
            var supplied = change["metadata"] is JsonObject fields ? StoredSessionCodec.DecodeSpace(fields) : null;
            if ((supplied ?? original) is not { } space || space.Id != id)
                throw new BrowserRuleException(BrowserRuleCodes.WrongSpaceIdentity);
            byId[id] = space with {
                Tabs = Edited(original?.Tabs, change[Key.Tabs], StoredSessionCodec.DecodeTab, tab => tab.Id),
                Folders = Edited(original?.Folders, change[Key.Folders], StoredSessionCodec.DecodeFolder, folder => folder.Id),
                SplitGroups = supplied?.SplitGroups ?? original!.SplitGroups,
                ArchivedTabs = Edited(original?.ArchivedTabs, change[Key.ArchivedTabs], StoredSessionCodec.DecodeArchivedTab,
                    archived => archived.Tab.Id),
                History = Edited(original?.History, change[Key.History], StoredSessionCodec.DecodeHistoryEntry, entry => entry.Id)
            };
        }
        var spaceOrder = delta["spaceOrder"] is JsonArray suppliedOrder
            ? suppliedOrder.Select(Id).ToArray() : session.Spaces.Select(s => s.Id).ToArray();
        if (spaceOrder.Distinct().Count() != spaceOrder.Length || spaceOrder.Any(id => !byId.ContainsKey(id)))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidSpaceOrder);
        var next = settings with { Spaces = spaceOrder.Select(id => byId[id]).ToArray() };
        if (!session.SpaceDeletions.All(settings.SpaceDeletions.Contains))
            throw new BrowserRuleException(BrowserRuleCodes.DeletionRequiresCommand);
        // A Space that is being deleted stays exactly as it was until it is removed.
        foreach (var deletion in settings.SpaceDeletions) {
            var original = session.Spaces.Single(s => s.Id == deletion.SpaceId);
            var retained = next.Spaces.SingleOrDefault(s => s.Id == deletion.SpaceId);
            if (retained is null || original != retained)
                throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
        }
        Validate(next);
        ValidateBorrowedSession(next);
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
        SessionState next;
        ulong revision;
        lock (Gate) {
            next = Prepare(expected, delta, nativeValueEdit: nativeValueEdit);
            revision = checked(Revision + 1);
            session = next; Revision = revision;
            storage?.Enqueue(session, Revision);
        }
        Published(next, followUp: null);
        return revision;
    }

    public static (ulong Source, ulong Destination) CommitPair(
        NativeSessionAuthority source, ulong sourceRevision, ReadOnlySpan<byte> sourceDelta,
        NativeSessionAuthority destination, ulong destinationRevision, ReadOnlySpan<byte> destinationDelta) {
        if (ReferenceEquals(source, destination)) throw new BrowserRuleException(BrowserRuleCodes.SameSessionTransfer);
        SessionState a, b;
        ulong ar, br;
        lock (Gate) {
            a = source.Prepare(sourceRevision, sourceDelta);
            b = destination.Prepare(destinationRevision, destinationDelta);
            ar = checked(source.Revision + 1); br = checked(destination.Revision + 1);
            source.session = a; destination.session = b;
            source.Revision = ar; destination.Revision = br;
            source.storage?.Enqueue(a, ar);
            destination.storage?.Enqueue(b, br);
        }
        source.Published(a, followUp: null);
        destination.Published(b, followUp: null);
        return (ar, br);
    }

    /// The stored parts of the accepted revision `expected`.
    internal NativeSessionCheckpoint Checkpoint(ulong expected) {
        lock (Gate) {
            if (expected != Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
            return new(session);
        }
    }

    #endregion
}
