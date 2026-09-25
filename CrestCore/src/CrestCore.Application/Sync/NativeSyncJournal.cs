using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Immutable sync state. Copies share records until a semantic transition
/// replaces them; failed transitions never publish clocks, records or pending IDs.
public sealed class NativeSyncJournal {
    #region Variables

    public const int MaximumBytes = 64 * 1024 * 1024;
    public const int MaximumRecords = 250_000;
    private readonly JsonObject metadata;
    private readonly Dictionary<string, JsonObject> records;
    private readonly HashSet<string> pending;
    private readonly Lazy<byte[]> encoded;
    internal IEnumerable<JsonObject> Records => records.Values;
    internal JsonNode Preferences => metadata["preferences"]!.DeepClone();
    /// How many records wait to upload.
    internal int PendingCount => pending.Count;
    /// How many records the journal holds, tombstones included.
    internal int RecordCount => records.Count;

    #endregion

    #region Constructors

    public NativeSyncJournal(ReadOnlySpan<byte> bytes) : this(Parse(bytes)) { }

    /// The journal `source`, a stored journal parsed once, which it takes
    /// over: nothing else may hold it.
    internal NativeSyncJournal(JsonObject source) {
        if (source["schemaVersion"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
        // Every member but the records, which the journal keeps by name.
        metadata = new JsonObject(source.Where(member => member.Key is not ("records" or "pendingRecordIDs"))
            .Select(member => KeyValuePair.Create(member.Key, member.Value?.DeepClone())));
        _ = Id(metadata["deviceID"]);
        records = RecordMap(source["records"]!.AsArray());
        pending = source["pendingRecordIDs"]!.AsArray().Select(n => Name(n!)).ToHashSet(StringComparer.Ordinal);
        if (!pending.IsSubsetOf(records.Keys)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncPending);
        ulong clock = metadata["logicalClock"]!.GetValue<ulong>();
        foreach (var record in records.Values) clock = Math.Max(clock, Clock(record));
        metadata["logicalClock"] = clock;
        encoded = new(Encode, true);
    }

    private NativeSyncJournal(JsonObject metadata, Dictionary<string, JsonObject> records, HashSet<string> pending) { this.metadata = metadata; this.records = records; this.pending = pending; encoded = new(Encode, true); }

    /// The journal of a device that has staged nothing yet: no records, the
    /// clock at zero, and every record category synced.
    public static NativeSyncJournal Fresh(Guid deviceId) => new(Encoding.UTF8.GetBytes(new JsonObject {
        ["schemaVersion"] = 1,
        ["deviceID"] = deviceId.ToString("D").ToUpperInvariant(),
        ["logicalClock"] = 0,
        ["preferences"] = new JsonObject {
            ["savedStructure"] = true,
            ["currentTabs"] = true,
            ["historyAndArchive"] = true,
            ["extensionSettings"] = true
        },
        ["records"] = new JsonArray(),
        ["pendingRecordIDs"] = new JsonArray()
    }.ToJsonString()));

    #endregion

    #region Actions - Decoding

    private static JsonObject Parse(ReadOnlySpan<byte> bytes) {
        if (bytes.Length is 0 or > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SyncSizeLimit);
        return JsonNode.Parse(bytes, documentOptions: new() { MaxDepth = 64 })!.AsObject();
    }

    private static Guid Id(JsonNode? node) => NativeSessionAuthority.Id(node);

    private static string Kind(JsonNode record) => record["id"]!["kind"]!.GetValue<string>();

    private static string Name(JsonNode id) => id["kind"]!.GetValue<string>() + ":" + Id(id["value"]).ToString("D");

    /// The name of the record a reference names.
    private static string Name(SyncRecordKind kind, Guid id) => kind.Name + ":" + id.ToString("D");

    private static SyncVersion Version(JsonNode record) {
        var version = record["version"]!;
        return new(version["logicalClock"]!.GetValue<ulong>(), Id(version["deviceID"]));
    }

    private static SyncRecordReference Reference(JsonNode record) =>
        new(SyncRecordKind.Named(Kind(record)) ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncKind),
            Id(record["id"]!["value"]));

    private static ulong Clock(JsonNode record) => record["version"]!["logicalClock"]!.GetValue<ulong>();

    private static JsonObject? Payload(JsonNode record) => record["payload"] as JsonObject;

    private static JsonObject Value(JsonNode payload) => payload["value"]!.AsObject();

    /// An archive reason this build does not know counts as a close, as the
    /// stored session reads it.
    private static ArchiveReason Known(string name) => ArchiveReason.Named(name) ?? ArchiveReason.Closed;

    private static JsonObject PayloadId(JsonObject payload) {
        string kind = payload["type"]!.GetValue<string>();
        var identity = kind == SyncRecordKinds.Archive ? Value(payload)["tab"]! : Value(payload);
        return new() { ["kind"] = kind, ["value"] = Id(identity["id"]).ToString("D").ToUpperInvariant() };
    }

    private static JsonNode PayloadSpace(JsonObject payload) => payload["type"]!.GetValue<string>() switch {
        SyncRecordKinds.Space => Value(payload)["id"]!,
        SyncRecordKinds.Archive => Value(payload)["tab"]!["spaceID"]!,
        _ => Value(payload)["spaceID"]!
    };

    #endregion

    #region Actions - Journal updates

    /// The journal of a restored checkpoint, owned by a new device identity so
    /// it never reissues a version it issued after the checkpoint was taken.
    /// Its records, clock and pending uploads are unchanged.
    public NativeSyncJournal Recovered(Guid deviceId) {
        if (deviceId == Id(metadata["deviceID"])) throw new BrowserRuleException(BrowserRuleCodes.InvalidRecoveryIdentity);
        var fields = metadata.DeepClone().AsObject();
        fields["deviceID"] = deviceId.ToString("D").ToUpperInvariant();
        return new(fields, new(records, StringComparer.Ordinal), new(pending, StringComparer.Ordinal));
    }

    public NativeSyncJournal Apply(ReadOnlySpan<byte> bytes) => Apply(Parse(bytes));

    /// The journal after the request `bytes` hold, a stage deleting each
    /// record it removes for the reason `removals` names for it.
    internal NativeSyncJournal Apply(ReadOnlySpan<byte> bytes, IReadOnlyDictionary<string, SyncDeletionReason> removals) =>
        Apply(Parse(bytes), removals);

    /// The Space the record `name` names belongs to here, or null when the
    /// journal holds no such record.
    internal Guid? SpaceOf(string name) => records.TryGetValue(name, out var record) ? Id(record["spaceID"]) : null;

    /// The journal after rebasing above `cloud`, records the cloud holds, from
    /// `session`, a whole session in the stored format that nothing else holds:
    /// each record is written above the cloud's and waits to upload. A record
    /// the session no longer holds is deleted for the reason `removals` names
    /// for it, else as superseded; `now` in seconds since 2001 dates the
    /// tombstones.
    internal NativeSyncJournal Overwrite(JsonObject session, JsonArray cloud, double now,
        IReadOnlyDictionary<string, SyncDeletionReason>? removals = null) {
        var request = new JsonObject {
            ["version"] = 1,
            ["operation"] = NativeSyncOperationCodes.Name(NativeSyncOperation.Overwrite),
            ["preferences"] = Preferences,
            ["arguments"] = new JsonObject { ["session"] = session, ["records"] = cloud, ["now"] = now }
        };
        return Apply(request, removals);
    }

    /// The journal after staging `session`, a whole session in the stored
    /// format that nothing else holds, under this journal's preferences.
    /// Records it no longer holds are deleted, where their absence authorizes a
    /// deletion, for the reason `removals` names for them by record name, else
    /// for `reason`; `now` in seconds since 2001 dates the tombstones.
    internal NativeSyncJournal Stage(JsonObject session, SyncDeletionReason reason, double now,
        IReadOnlyDictionary<string, SyncDeletionReason>? removals = null) {
        var request = new JsonObject {
            ["version"] = 1,
            ["operation"] = NativeSyncOperationCodes.Name(NativeSyncOperation.Stage),
            ["preferences"] = Preferences,
            ["arguments"] = new JsonObject { ["session"] = session, ["deletionReason"] = reason.Name, ["now"] = now }
        };
        return Apply(request, removals);
    }

    /// The journal after `request`. A stage or an overwrite deletes each record
    /// it removes for the reason `removals` names for it, else for the
    /// request's own, or as superseded.
    internal NativeSyncJournal Apply(JsonObject request, IReadOnlyDictionary<string, SyncDeletionReason>? removals = null) {
        if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
        var fields = metadata.DeepClone().AsObject();
        fields["preferences"] = request["preferences"]!.DeepClone();
        var next = new Dictionary<string, JsonObject>(records, StringComparer.Ordinal);
        var queued = new HashSet<string>(pending, StringComparer.Ordinal);
        ulong clock = fields["logicalClock"]!.GetValue<ulong>();
        var operation = NativeSyncOperationCodes.Parse(request["operation"]!.GetValue<string>());
        var args = request["arguments"]!.AsObject();
        JsonObject Version() {
            if (clock == ulong.MaxValue) throw new BrowserRuleException(BrowserRuleCodes.SyncClockExhausted);
            return new() { ["logicalClock"] = ++clock, ["deviceID"] = fields["deviceID"]!.DeepClone() };
        }
        JsonObject Save(JsonObject payload) {
            var id = PayloadId(payload);
            var result = next.TryGetValue(Name(id), out var previous) ? previous.DeepClone().AsObject() : new JsonObject();
            result["id"] = id; result["spaceID"] = PayloadSpace(payload).DeepClone();
            result["payload"] = payload.DeepClone(); result["version"] = Version(); result.Remove("tombstone");
            return result;
        }
        JsonObject Delete(JsonObject previous, SyncDeletionReason reason) {
            double now = args["now"]!.GetValue<double>();
            if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncDate);
            return new() {
                ["id"] = previous["id"]!.DeepClone(),
                ["spaceID"] = previous["spaceID"]!.DeepClone(),
                ["version"] = Version(),
                ["tombstone"] = new JsonObject { ["reason"] = reason.Name, ["deletedAt"] = now }
            };
        }
        if (operation is NativeSyncOperation.Merge or NativeSyncOperation.Replace or NativeSyncOperation.Overwrite) {
            var incoming = RecordMap(args["records"]!.AsArray());
            foreach (var record in incoming.Values) clock = Math.Max(clock, Clock(record));
            // A record at the last clock would leave this journal no version to
            // write any later edit at.
            if (clock == ulong.MaxValue) throw new BrowserRuleException(BrowserRuleCodes.SyncClockExhausted);
            if (operation == NativeSyncOperation.Replace) { next = incoming; queued.Clear(); } else foreach (var (id, remote) in incoming) {
                if (operation == NativeSyncOperation.Overwrite || !next.TryGetValue(id, out var local)) { next[id] = remote; continue; }
                var resolved = NativeSyncEvaluator.Resolve(local, remote);
                next[id] = resolved;
                // An acknowledged local winner does not become pending merely
                // because a fetch races an older server version.
                if (!NativeSyncEvaluator.Equivalent(resolved, local) && !NativeSyncEvaluator.Equivalent(resolved, remote)) queued.Add(id);
            }
        }
        if (operation is NativeSyncOperation.Stage or NativeSyncOperation.Overwrite) {
            var desired = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
            var session = args["session"] as JsonObject;
            var cleaning = (session?["spaceDeletions"] as JsonArray ?? new()).Select(n => Id(n!["spaceID"])).ToHashSet();
            var payloads = session is null ? args["payloads"]!.AsArray()
                : NativeSyncProjection.Project(session, fields["preferences"]!, records.Values);
            foreach (var node in payloads) {
                var payload = node!.AsObject();
                // Pending cleanup is local recovery state. It neither edits
                // remote records nor revives an incoming deletion tombstone.
                if (cleaning.Contains(Id(PayloadSpace(payload)))) continue;
                var id = PayloadId(payload);
                next.TryGetValue(Name(id), out var previous);
                var previousPayload = previous is null ? null : Payload(previous);
                // Closing/restoring changes the record kind, not the tab's
                // identity. Carry its additive fields across that transition.
                string kind = payload["type"]!.GetValue<string>();
                if (previousPayload is null && kind is SyncRecordKinds.Tab or SyncRecordKinds.Archive
                    && next.TryGetValue((kind == SyncRecordKinds.Tab ? SyncRecordKinds.Archive : SyncRecordKinds.Tab)
                        + ":" + Id(id["value"]).ToString("D"), out var counterpart)
                    && Payload(counterpart) is { } other) {
                    var oldTab = kind == SyncRecordKinds.Tab ? Value(other)["tab"]! : Value(other);
                    previousPayload = new JsonObject {
                        ["type"] = kind,
                        ["value"] = kind == SyncRecordKinds.Tab ? oldTab.DeepClone() : new JsonObject { ["tab"] = oldTab.DeepClone() }
                    };
                }
                payload = NativeSyncCompatibility.Preserve(payload, previousPayload);
                if (!desired.TryAdd(Name(PayloadId(payload)), payload)) throw new BrowserRuleException(BrowserRuleCodes.DuplicateSyncRecord);
            }
            if (desired.Count > MaximumRecords) throw new BrowserRuleException(BrowserRuleCodes.SyncRecordLimit);
            if (operation == NativeSyncOperation.Overwrite) {
                queued.Clear();
                foreach (string id in next.Keys.Union(desired.Keys).Order(StringComparer.Ordinal).ToArray()) {
                    if (next.TryGetValue(id, out var cleaningRecord) && cleaning.Contains(Id(cleaningRecord["spaceID"]))) continue;
                    if (desired.TryGetValue(id, out var payload)) next[id] = Save(payload);
                    else {
                        if (Payload(next[id]) is { } old && !Includes(fields["preferences"]!, old)) continue;
                        next[id] = Delete(next[id], removals?.GetValueOrDefault(id) ?? SyncDeletionReason.Superseded);
                    }
                    queued.Add(id);
                }
            } else {
                var fallback = SyncDeletionReason.Named(args["deletionReason"]!.GetValue<string>())
                    ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncDeletion);
                // Parent evidence is from the accepted journal before staging.
                var spaces = records.Values.Where(r => Kind(r) == SyncRecordKinds.Space).Select(r => Id(r["spaceID"])).ToHashSet();
                var folderRecords = records.Values.Where(r => Kind(r) == SyncRecordKinds.Folder).ToDictionary(r => Id(r["id"]!["value"]));
                var archiveReasons = session is null
                    ? args["archiveReasons"]!.AsArray().ToDictionary(n => Id(n!["id"]), n => Known(n!["reason"]!.GetValue<string>()))
                    : NativeSyncProjection.Items(session, "spaces").SelectMany(s => NativeSyncProjection.Items(s!, StoredSessionCodec.Key.ArchivedTabs))
                        .ToDictionary(a => Id(a!["tab"]!["id"]), a => Known(NativeSyncProjection.ArchiveReasonName(a!)));
                foreach (var (id, payload) in desired.OrderBy(p => p.Key, StringComparer.Ordinal)) {
                    if (next.TryGetValue(id, out var existing) && NativeSyncEvaluator.Equivalent(Payload(existing), payload)) continue;
                    next[id] = Save(payload); queued.Add(id);
                }
                foreach (var (id, record) in next.ToArray()) {
                    if (cleaning.Contains(Id(record["spaceID"]))) continue;
                    if (Payload(record) is not { } payload || !Includes(fields["preferences"]!, payload) || desired.ContainsKey(id)) continue;
                    SyncDeletionReason? reason;
                    if (!Portable(payload)) reason = SyncDeletionReason.Superseded;
                    else {
                        if (!spaces.Contains(Id(record["spaceID"])) || !AncestryArrived(payload, folderRecords)) continue;
                        string kind = Kind(record);
                        var placement = kind == SyncRecordKinds.Tab ? TabPlacement.Named(Value(payload)["placement"]!.GetValue<string>()) ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncPlacement) : (TabPlacement?)null;
                        reason = SyncDeletionPolicy.Reason(kind, placement, archiveReasons.GetValueOrDefault(Id(record["id"]!["value"])),
                            desired.ContainsKey(SyncRecordKinds.Space + ":" + Id(record["spaceID"]).ToString("D")),
                            removals?.GetValueOrDefault(id) ?? fallback);
                    }
                    if (reason is null) continue;
                    next[id] = Delete(record, reason); queued.Add(id);
                }
            }
        } else if (operation == NativeSyncOperation.Acknowledge) {
            foreach (var item in args["acknowledgements"]!.AsArray()) {
                string id = Name(item!["id"]!);
                if (item["version"] is null || next.TryGetValue(id, out var record) && NativeSyncEvaluator.Equivalent(item["version"], record["version"]))
                    queued.Remove(id);
            }
        } else if (operation is not (NativeSyncOperation.Merge or NativeSyncOperation.Replace or NativeSyncOperation.Preferences))
            throw new BrowserRuleException(BrowserRuleCodes.UnknownSyncOperation);
        if (next.Count > MaximumRecords) throw new BrowserRuleException(BrowserRuleCodes.SyncRecordLimit);
        fields["logicalClock"] = clock;
        return new(fields, next, queued);
    }

    private static bool Includes(JsonNode preferences, JsonObject payload) => payload["type"]!.GetValue<string>() switch {
        SyncRecordKinds.Space => true,
        SyncRecordKinds.Folder => preferences[TabPlacement.Named(Value(payload)["location"]!.GetValue<string>())?.IsDurable == false ? "currentTabs" : "savedStructure"]!.GetValue<bool>(),
        SyncRecordKinds.Tab => preferences[TabPlacement.Named(Value(payload)["placement"]!.GetValue<string>())?.IsDurable == false ? "currentTabs" : "savedStructure"]!.GetValue<bool>(),
        _ => preferences["historyAndArchive"]!.GetValue<bool>()
    };

    private static bool Portable(JsonObject payload) {
        string kind = payload["type"]!.GetValue<string>();
        if (kind is SyncRecordKinds.Space or SyncRecordKinds.Folder) return true;
        var value = kind == SyncRecordKinds.Archive ? Value(payload)["tab"]! : Value(payload);
        return kind == SyncRecordKinds.History ? SyncContentPolicy.Includes(value["url"]?.GetValue<string>())
            : SyncContentPolicy.IncludesTab(value["url"]?.GetValue<string>(), value["nativeContent"] is not null, value["savedURL"]?.GetValue<string>());
    }

    private static bool AncestryArrived(JsonObject payload, Dictionary<Guid, JsonObject> folders) {
        var value = Value(payload);
        JsonNode? next = payload["type"]!.GetValue<string>() switch {
            SyncRecordKinds.Folder => value["parentID"],
            SyncRecordKinds.Tab when TabPlacement.Named(value["placement"]!.GetValue<string>())?.HoldsFolders != false => value["folderID"],
            _ => null
        };
        var seen = new HashSet<Guid>();
        while (next is not null) {
            var id = Id(next);
            if (!folders.TryGetValue(id, out var record)) return false;
            if (!seen.Add(id)) return true; // Materialization rejects cycles.
            if (Payload(record) is not { } folder) return false;
            next = Value(folder)["parentID"];
        }
        return true;
    }

    #endregion

    #region Actions - Uploads

    /// The records that wait to upload, in the order of their names.
    internal IReadOnlyList<SyncRecordReference> PendingReferences() =>
        [.. pending.Order(StringComparer.Ordinal).Select(name => Reference(records[name]))];

    /// Whether the journal holds the record `reference` names.
    internal bool Holds(SyncRecordReference reference) => records.ContainsKey(Name(reference.Kind, reference.Id));

    /// The record `reference` names as the cloud transport uploads it, its
    /// body in the CloudKit form at the schema it needs, or null when the
    /// journal holds no such record or holds one this device does not send:
    /// one no client reads, or one naming an address it cannot spell as every
    /// client parses it.
    internal SyncRecord? Uploading(SyncRecordReference reference) {
        if (!records.TryGetValue(Name(reference.Kind, reference.Id), out var record)) return null;
        var tombstone = record["tombstone"];
        var space = Id(record["spaceID"]);
        try {
            var body = SyncRecordBody.Read(tombstone ?? record["payload"], tombstone is not null, SyncPayloadForm.Journal);
            body.RequireSendable(reference.Kind, reference.Id, space);
            return new(reference.Kind, reference.Id, space, Version(record), body.Schema, body.Bytes(SyncPayloadForm.Cloud), tombstone is not null);
        } catch (UnreadableSyncPayloadException) {
            return null;
        }
    }

    /// The journal once the cloud saved `uploaded`: each record it holds at
    /// exactly the version the cloud saved no longer waits to upload. A record
    /// written again since, or no longer held, is left as it is. The records
    /// themselves do not change.
    internal NativeSyncJournal Acknowledge(IReadOnlyList<UploadedRecord> uploaded) {
        var queued = new HashSet<string>(pending, StringComparer.Ordinal);
        foreach (var upload in uploaded) {
            string name = Name(upload.Record.Kind, upload.Record.Id);
            if (records.TryGetValue(name, out var record) && Version(record) == upload.Version) queued.Remove(name);
        }
        return new(metadata.DeepClone().AsObject(), records, queued);
    }

    /// How this journal compares with `cloud`, every record the cloud holds;
    /// see `CloudContentComparison`. A journal that `holdsNothing` counts as
    /// empty. A cloud record this build cannot read is left out, as the
    /// transport leaves it out of everything else.
    ///
    /// Both sides compare in the CloudKit form. The cloud holds each date as
    /// the seconds since 1970 some client computed from its journal's seconds
    /// since 2001, so converting this device's dates the same way reproduces
    /// the cloud's to the bit when the content is the same: a date this device
    /// uploaded converts with the same arithmetic, and one it downloaded
    /// converts back exactly. Comparing in the journal's form would see the
    /// last bit of a converted date differ where nothing did.
    internal CloudContentComparison Comparing(IReadOnlyList<SyncRecord> cloud, bool holdsNothing) {
        IReadOnlyDictionary<string, JsonObject> device = holdsNothing ? new Dictionary<string, JsonObject>() : records;
        var arrived = new Dictionary<string, (Guid Space, bool IsTombstone, JsonNode Body)>(StringComparer.Ordinal);
        foreach (var record in cloud) {
            if (record.Schema is < 1 or > SyncRecordBody.NewestSchema) continue;
            try {
                var body = SyncRecordBody.Read(record.Body, record.IsTombstone, SyncPayloadForm.Cloud);
                body.RequireRecord(record.Kind, record.Id, record.SpaceId);
                arrived[Name(record.Kind, record.Id)] = (record.SpaceId, record.IsTombstone, body.Write(SyncPayloadForm.Cloud));
            } catch (UnreadableSyncPayloadException) {
                // Left out; see the summary.
            }
        }
        bool matches = arrived.Count == device.Count && device.All(held =>
            arrived.TryGetValue(held.Key, out var other) && Id(held.Value["spaceID"]) == other.Space
            && (held.Value["tombstone"] is not null) == other.IsTombstone
            && NativeSyncEvaluator.Equivalent(CloudForm(held.Value), other.Body));
        return new(matches, device.Count, arrived.Count,
            device.Values.Count(record => Kind(record) == SyncRecordKinds.Space && Payload(record) is not null),
            arrived.Count(record => record.Key.StartsWith(SyncRecordKind.Space.Name + ":", StringComparison.Ordinal) && !record.Value.IsTombstone));
    }

    /// The body of `record`, which this journal holds, in the CloudKit form, or
    /// as the journal holds it when no client reads it.
    private static JsonNode? CloudForm(JsonObject record) {
        var tombstone = record["tombstone"];
        try {
            return SyncRecordBody.Read(tombstone ?? record["payload"], tombstone is not null, SyncPayloadForm.Journal).Write(SyncPayloadForm.Cloud);
        } catch (UnreadableSyncPayloadException) {
            return tombstone ?? record["payload"];
        }
    }

    #endregion

    #region Actions - Encoding

    public byte[] Read() => encoded.Value;

    private byte[] Encode() {
        var value = metadata.DeepClone().AsObject();
        value["records"] = new JsonArray(records.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => p.Value.DeepClone()).ToArray());
        value["pendingRecordIDs"] = new JsonArray(pending.Order(StringComparer.Ordinal).Select(id => records[id]["id"]!.DeepClone()).ToArray());
        var result = Encoding.UTF8.GetBytes(value.ToJsonString());
        if (result.Length > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SyncSizeLimit);
        return result;
    }

    #endregion

    #region Mutators

    private static Dictionary<string, JsonObject> RecordMap(JsonArray values) {
        if (values.Count > MaximumRecords) throw new BrowserRuleException(BrowserRuleCodes.SyncRecordLimit);
        var result = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
        foreach (var value in values) {
            NativeSyncEvaluator.ValidateRecord(value!.AsObject());
            if (!result.TryAdd(Name(value["id"]!), value.AsObject())) throw new BrowserRuleException(BrowserRuleCodes.DuplicateSyncRecord);
        }
        return result;
    }

    #endregion
}
