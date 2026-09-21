using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Owns the native app's durable session during the command-by-command migration.
/// Native views propose value deltas; only an accepted revision becomes visible.
/// Published documents are immutable, so storage can serialize an older checkpoint
/// on its worker while the UI continues editing the current revision.
public sealed partial class NativeSessionAuthority {
    #region Variables

    public const int MaximumBytes = 64 * 1024 * 1024;
    internal static readonly object Gate = new();
    private SessionDocument document;
    private NativeSessionReplacement? replacement;
    private readonly BrowserWorkspaceKind workspaceKind;
    private readonly bool privateBrowsing;
    public ulong Revision { get; private set; } = 1;
    public Adapter? Engine { get; private set; }
    private static readonly IReadOnlyList<string> Sections = SpaceSections.Names;

    #endregion

    #region Constructors

    public NativeSessionAuthority(ReadOnlySpan<byte> bytes) {
        var input = Parse(bytes);
        workspaceKind = input["coreWorkspaceKind"]?.GetValue<string>() switch {
            null or "persistent" => BrowserWorkspaceKind.Persistent,
            "private" => BrowserWorkspaceKind.Private,
            "temporary" => throw new BrowserRuleException(BrowserRuleCodes.BorrowedSourceRequired),
            _ => throw new BrowserRuleException(BrowserRuleCodes.InvalidWorkspaceKind)
        };
        privateBrowsing = input["corePrivateBrowsing"]?.GetValue<bool>() ?? workspaceKind == BrowserWorkspaceKind.Private;
        document = new(Fields(input, ["spaces", "coreWorkspaceKind", "corePrivateBrowsing"]), input["spaces"]!.AsArray().Select(node =>
            new SpaceDocument(Fields(node!.AsObject(), Sections), Sections.ToDictionary(section => section,
                section => (IReadOnlyList<JsonNode>)node[section]!.AsArray().Select(item => item!.DeepClone()).ToArray()))).ToArray());
        Validate(document);
    }

    #endregion

    #region Actions - Engine registration

    /// Process-local registration shares the transport descriptor contract. It
    /// cannot be changed by session edits, restored files or remote sync records.
    public void RegisterEngine(ReadOnlySpan<byte> descriptor) {
        var engine = Protocol.Descriptor(descriptor);
        if (engine.Role != AdapterRoles.Engine || !engine.Supports(EngineCapabilities.Pages)
            || !engine.Supports(EngineCapabilities.Navigation))
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
        if (value is JsonObject obj) value = obj["rawValue"];
        var id = Guid.Parse(value!.GetValue<string>());
        if (id == Guid.Empty) throw new BrowserRuleException(BrowserRuleCodes.InvalidIdentity);
        return id;
    }

    private static Guid RecordId(JsonNode value, string section) => Id(section == "archivedTabs" ? value["tab"]!["id"] : value["id"]);

    private static JsonObject Fields(JsonObject input, IReadOnlyCollection<string> excluded)
        => new(input.Where(f => !excluded.Contains(f.Key)).Select(f => new KeyValuePair<string, JsonNode?>(f.Key, f.Value?.DeepClone())));

    private static void Validate(SessionDocument value) {
        var spaces = value.Spaces;
        var ids = new HashSet<Guid>(); var tabs = new HashSet<Guid>(); var profiles = new HashSet<Guid>();
        foreach (var space in spaces) {
            if (!ids.Add(Id(space.Metadata["id"]))) throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpace);
            // A Space is exactly one profile and a profile belongs to exactly one
            // Space. Two Spaces sharing a profile would share cookies, credentials
            // and extension access across an isolation boundary the user relies on,
            // and would make "which Space owns this profile" unanswerable.
            if (!profiles.Add(Id(space.Metadata["profile"]!["id"])))
                throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpaceProfile);
            foreach (var tab in space.Tabs)
                if (!tabs.Add(Id(tab!["id"]))) throw new BrowserRuleException(BrowserRuleCodes.DuplicateTab);
        }
        var pendingIds = new HashSet<Guid>();
        foreach (var deletion in Deletions(value.Metadata)) {
            var id = Id(deletion!["spaceID"]);
            var profile = Id(deletion["profileID"]);
            _ = Id(deletion["operationID"]);
            if (!pendingIds.Add(id) || !spaces.Any(s => Id(s.Metadata["id"]) == id && Id(s.Metadata["profile"]!["id"]) == profile))
                throw new BrowserRuleException(BrowserRuleCodes.InvalidDeletionIntent);
        }
        // An empty temporary workspace and a briefly stale window selection are
        // valid native states. Window reconciliation handles their presentation.
    }

    #endregion

    #region Actions - Session revisions

    private SessionDocument Prepare(ulong expected, ReadOnlySpan<byte> bytes, JsonNode? authorizedDeletions = null) {
        RequireWritable();
        if (expected != Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
        var delta = Parse(bytes);
        if (delta["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
        var metadata = delta["metadata"] is JsonObject suppliedMetadata ? Fields(suppliedMetadata, ["spaces"]) : document.Metadata;
        if (!EqualDeletionIntents(metadata["spaceDeletions"], authorizedDeletions ?? document.Metadata["spaceDeletions"]))
            throw new BrowserRuleException(BrowserRuleCodes.DeletionRequiresCommand);
        var byId = document.Spaces.ToDictionary(s => Id(s.Metadata["id"]));
        foreach (var node in delta["spaces"]!.AsArray()) {
            var change = node!.AsObject(); var id = Id(change["id"]);
            byId.TryGetValue(id, out var original);
            var fields = change["metadata"] is JsonObject supplied ? Fields(supplied, Sections) : original?.Metadata;
            if (fields is null || Id(fields["id"]) != id) throw new BrowserRuleException(BrowserRuleCodes.WrongSpaceIdentity);
            var sections = Sections.ToDictionary(section => section,
                section => original?.Sections[section] ?? (IReadOnlyList<JsonNode>)System.Array.Empty<JsonNode>());
            foreach (var section in Sections) {
                if (change[section] is not JsonObject edits) continue;
                if (edits["replace"] is JsonArray replacement) { sections[section] = replacement.Select(item => item!.DeepClone()).ToArray(); continue; }
                var previous = sections[section];
                var records = previous.ToDictionary(v => RecordId(v!, section), v => v!);
                foreach (var removed in edits["remove"]!.AsArray()) records.Remove(Id(removed));
                foreach (var item in edits["upsert"]!.AsArray()) records[RecordId(item!, section)] = item!.DeepClone();
                var order = edits["order"] is JsonArray suppliedRecords
                    ? suppliedRecords.Select(Id).ToArray() : previous.Select(v => RecordId(v!, section)).ToArray();
                if (order.Length != records.Count || order.Distinct().Count() != order.Length || order.Any(id => !records.ContainsKey(id)))
                    throw new BrowserRuleException(BrowserRuleCodes.InvalidRecordOrder);
                sections[section] = order.Select(key => records[key]).ToArray();
            }
            byId[id] = new(fields, sections);
        }
        var spaceOrder = delta["spaceOrder"] is JsonArray suppliedOrder
            ? suppliedOrder.Select(Id).ToArray() : document.Spaces.Select(s => Id(s.Metadata["id"])).ToArray();
        if (spaceOrder.Distinct().Count() != spaceOrder.Length || spaceOrder.Any(id => !byId.ContainsKey(id)))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidSpaceOrder);
        var next = new SessionDocument(metadata, spaceOrder.Select(id => byId[id]).ToArray());
        foreach (var existing in Deletions(document.Metadata))
            if (!Deletions(metadata).Any(d => SameDeletionIntent(d!, existing!)))
                throw new BrowserRuleException(BrowserRuleCodes.DeletionRequiresCommand);
        foreach (var deletion in Deletions(metadata)) {
            var id = Id(deletion!["spaceID"]);
            var original = document.Spaces.Single(s => Id(s.Metadata["id"]) == id);
            var retained = next.Spaces.SingleOrDefault(s => Id(s.Metadata["id"]) == id);
            if (retained is null || !JsonNode.DeepEquals(Fields(original.Metadata, ["selectedTabID"]), Fields(retained.Metadata, ["selectedTabID"]))
                || Sections.Any(section => original.Sections[section].Count != retained.Sections[section].Count
                    || original.Sections[section].Zip(retained.Sections[section]).Any(pair => !JsonNode.DeepEquals(pair.First, pair.Second))))
                throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
        }
        Validate(next);
        ValidateBorrowedDocument(next);
        return next;
    }

    private void RequireWritable(bool requireCurrentBorrowedPolicy = true) {
        if (released) throw new BrowserRuleException(BrowserRuleCodes.SessionReleased);
        if (replacement is not null) throw new BrowserRuleException(BrowserRuleCodes.SessionTransactionInProgress);
        if (borrowedSource is not null) {
            _ = RequireBorrowedSource();
            if (requireCurrentBorrowedPolicy) RequireBorrowedRevision(borrowedSourceRevision);
        }
    }

    public ulong Commit(ulong expected, ReadOnlySpan<byte> delta) {
        lock (Gate) {
            var next = Prepare(expected, delta);
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

    public NativeSessionCheckpoint Checkpoint(ulong expected, ReadOnlySpan<byte> selection) {
        lock (Gate) {
            if (expected != Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
            return new(document, Parse(selection));
        }
    }

    #endregion
}
