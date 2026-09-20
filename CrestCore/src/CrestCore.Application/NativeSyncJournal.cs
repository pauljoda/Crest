using System.Text;
using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Immutable sync state. Copies share records until a semantic transition
/// replaces them; failed transitions never publish clocks, records or pending IDs.
public sealed class NativeSyncJournal
{
    public const int MaximumBytes = 64 * 1024 * 1024;
    public const int MaximumRecords = 250_000;
    private readonly JsonObject metadata;
    private readonly Dictionary<string, JsonObject> records;
    private readonly HashSet<string> pending;
    private readonly Lazy<byte[]> encoded;

    public NativeSyncJournal(ReadOnlySpan<byte> bytes)
    {
        var source = Parse(bytes);
        if (source["schemaVersion"]!.GetValue<int>() != 1) throw new BrowserRuleException("version_mismatch");
        metadata = source.DeepClone().AsObject();
        metadata.Remove("records"); metadata.Remove("pendingRecordIDs");
        _ = Id(metadata["deviceID"]);
        records = RecordMap(source["records"]!.AsArray());
        pending = source["pendingRecordIDs"]!.AsArray().Select(n => Name(n!)).ToHashSet(StringComparer.Ordinal);
        if (!pending.IsSubsetOf(records.Keys)) throw new BrowserRuleException("invalid_sync_pending");
        ulong clock = metadata["logicalClock"]!.GetValue<ulong>();
        foreach (var record in records.Values) clock = Math.Max(clock, Clock(record));
        metadata["logicalClock"] = clock;
        encoded = new(Encode, true);
    }

    private NativeSyncJournal(JsonObject metadata, Dictionary<string, JsonObject> records, HashSet<string> pending)
    { this.metadata = metadata; this.records = records; this.pending = pending; encoded = new(Encode, true); }

    private static JsonObject Parse(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length is 0 or > MaximumBytes) throw new BrowserRuleException("sync_size_limit");
        return JsonNode.Parse(bytes, documentOptions: new() { MaxDepth = 64 })!.AsObject();
    }
    private static Guid Id(JsonNode? node) => NativeSessionAuthority.Id(node);
    private static string Kind(JsonNode record) => record["id"]!["kind"]!.GetValue<string>();
    private static string Name(JsonNode id) => id["kind"]!.GetValue<string>() + ":" + Id(id["value"]).ToString("D");
    private static ulong Clock(JsonNode record) => record["version"]!["logicalClock"]!.GetValue<ulong>();
    private static JsonObject? Payload(JsonNode record) => record["payload"] as JsonObject;
    private static JsonObject Value(JsonNode payload) => payload["value"]!.AsObject();
    private static JsonObject PayloadId(JsonObject payload)
    {
        string kind = payload["type"]!.GetValue<string>();
        var identity = kind == "archive" ? Value(payload)["tab"]! : Value(payload);
        return new() { ["kind"] = kind, ["value"] = Id(identity["id"]).ToString("D").ToUpperInvariant() };
    }
    private static JsonNode PayloadSpace(JsonObject payload) => payload["type"]!.GetValue<string>() switch
    { "space" => Value(payload)["id"]!, "archive" => Value(payload)["tab"]!["spaceID"]!, _ => Value(payload)["spaceID"]! };
    private static Dictionary<string, JsonObject> RecordMap(JsonArray values)
    {
        if (values.Count > MaximumRecords) throw new BrowserRuleException("sync_record_limit");
        var result = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
        foreach (var value in values)
        {
            NativeSyncEvaluator.ValidateRecord(value!.AsObject());
            if (!result.TryAdd(Name(value["id"]!), value.AsObject())) throw new BrowserRuleException("duplicate_sync_record");
        }
        return result;
    }

    public NativeSyncJournal Apply(ReadOnlySpan<byte> bytes)
    {
        var request = Parse(bytes);
        if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException("version_mismatch");
        var fields = metadata.DeepClone().AsObject();
        fields["preferences"] = request["preferences"]!.DeepClone();
        var next = new Dictionary<string, JsonObject>(records, StringComparer.Ordinal);
        var queued = new HashSet<string>(pending, StringComparer.Ordinal);
        ulong clock = fields["logicalClock"]!.GetValue<ulong>();
        var operation = request["operation"]!.GetValue<string>();
        var args = request["arguments"]!.AsObject();
        JsonObject Version()
        {
            if (clock == ulong.MaxValue) throw new BrowserRuleException("sync_clock_exhausted");
            return new() { ["logicalClock"] = ++clock, ["deviceID"] = fields["deviceID"]!.DeepClone() };
        }
        JsonObject Save(JsonObject payload) => new()
        {
            ["id"] = PayloadId(payload), ["spaceID"] = PayloadSpace(payload).DeepClone(),
            ["payload"] = payload.DeepClone(), ["version"] = Version()
        };
        JsonObject Delete(JsonObject previous, string reason)
        {
            double now = args["now"]!.GetValue<double>();
            if (!double.IsFinite(now)) throw new BrowserRuleException("invalid_sync_date");
            return new() { ["id"] = previous["id"]!.DeepClone(), ["spaceID"] = previous["spaceID"]!.DeepClone(),
                ["version"] = Version(), ["tombstone"] = new JsonObject { ["reason"] = reason, ["deletedAt"] = now } };
        }
        if (operation is "merge" or "replace" or "overwrite")
        {
            var incoming = RecordMap(args["records"]!.AsArray());
            foreach (var record in incoming.Values) clock = Math.Max(clock, Clock(record));
            if (operation == "replace") { next = incoming; queued.Clear(); }
            else foreach (var (id, remote) in incoming)
            {
                if (operation == "overwrite" || !next.TryGetValue(id, out var local)) { next[id] = remote; continue; }
                var resolved = NativeSyncEvaluator.Resolve(local, remote);
                next[id] = resolved;
                // An acknowledged local winner does not become pending merely
                // because a fetch races an older server version.
                if (!NativeSyncEvaluator.Equivalent(resolved, local) && !NativeSyncEvaluator.Equivalent(resolved, remote)) queued.Add(id);
            }
        }
        if (operation is "stage" or "overwrite")
        {
            var desired = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
            var session = args["session"] as JsonObject;
            var payloads = session is null ? args["payloads"]!.AsArray()
                : NativeSyncProjection.Project(session, fields["preferences"]!, records.Values);
            foreach (var node in payloads)
            {
                var payload = node!.AsObject();
                if (!desired.TryAdd(Name(PayloadId(payload)), payload)) throw new BrowserRuleException("duplicate_sync_record");
            }
            if (desired.Count > MaximumRecords) throw new BrowserRuleException("sync_record_limit");
            if (operation == "overwrite")
            {
                queued.Clear();
                foreach (string id in next.Keys.Union(desired.Keys).Order(StringComparer.Ordinal).ToArray())
                {
                    if (desired.TryGetValue(id, out var payload)) next[id] = Save(payload);
                    else
                    {
                        if (Payload(next[id]) is { } old && !Includes(fields["preferences"]!, old)) continue;
                        next[id] = Delete(next[id], "superseded");
                    }
                    queued.Add(id);
                }
            }
            else
            {
                // Parent evidence is from the accepted journal before staging.
                var spaces = records.Values.Where(r => Kind(r) == "space").Select(r => Id(r["spaceID"])).ToHashSet();
                var folderRecords = records.Values.Where(r => Kind(r) == "folder").ToDictionary(r => Id(r["id"]!["value"]));
                var archiveReasons = session is null
                    ? args["archiveReasons"]!.AsArray().ToDictionary(n => Id(n!["id"]), n => n!["reason"]!.GetValue<string>())
                    : NativeSyncProjection.Items(session, "spaces").SelectMany(s => NativeSyncProjection.Items(s!, "archivedTabs"))
                        .ToDictionary(a => Id(a!["tab"]!["id"]), a => NativeSyncProjection.ArchiveReason(a!));
                foreach (var (id, payload) in desired.OrderBy(p => p.Key, StringComparer.Ordinal))
                {
                    if (next.TryGetValue(id, out var existing) && NativeSyncEvaluator.Equivalent(Payload(existing), payload)) continue;
                    next[id] = Save(payload); queued.Add(id);
                }
                foreach (var (id, record) in next.ToArray())
                {
                    if (Payload(record) is not { } payload || !Includes(fields["preferences"]!, payload) || desired.ContainsKey(id)) continue;
                    string? reason;
                    if (!Portable(payload)) reason = "superseded";
                    else
                    {
                        if (!spaces.Contains(Id(record["spaceID"])) || !AncestryArrived(payload, folderRecords)) continue;
                        string kind = Kind(record);
                        var placement = kind == "tab" ? Enum.Parse<TabPlacement>(Value(payload)["placement"]!.GetValue<string>(), true) : (TabPlacement?)null;
                        reason = SyncDeletionPolicy.Reason(kind, placement, archiveReasons.GetValueOrDefault(Id(record["id"]!["value"])),
                            desired.ContainsKey("space:" + Id(record["spaceID"]).ToString("D")), args["deletionReason"]!.GetValue<string>());
                    }
                    if (reason is null) continue;
                    next[id] = Delete(record, reason); queued.Add(id);
                }
            }
        }
        else if (operation == "acknowledge")
        {
            foreach (var item in args["acknowledgements"]!.AsArray())
            {
                string id = Name(item!["id"]!);
                if (item["version"] is null || next.TryGetValue(id, out var record) && NativeSyncEvaluator.Equivalent(item["version"], record["version"]))
                    queued.Remove(id);
            }
        }
        else if (operation is not ("merge" or "replace" or "preferences")) throw new BrowserRuleException("unknown_sync_operation");
        if (next.Count > MaximumRecords) throw new BrowserRuleException("sync_record_limit");
        fields["logicalClock"] = clock;
        return new(fields, next, queued);
    }

    private static bool Includes(JsonNode preferences, JsonObject payload) => payload["type"]!.GetValue<string>() switch
    {
        "space" => true,
        "folder" => preferences[Value(payload)["location"]!.GetValue<string>() == "current" ? "currentTabs" : "savedStructure"]!.GetValue<bool>(),
        "tab" => preferences[Value(payload)["placement"]!.GetValue<string>() == "current" ? "currentTabs" : "savedStructure"]!.GetValue<bool>(),
        _ => preferences["historyAndArchive"]!.GetValue<bool>()
    };
    private static bool Portable(JsonObject payload)
    {
        string kind = payload["type"]!.GetValue<string>();
        if (kind is "space" or "folder") return true;
        var value = kind == "archive" ? Value(payload)["tab"]! : Value(payload);
        return kind == "history" ? SyncContentPolicy.Includes(value["url"]?.GetValue<string>())
            : SyncContentPolicy.IncludesTab(value["url"]?.GetValue<string>(), value["nativeContent"] is not null, value["savedURL"]?.GetValue<string>());
    }
    private static bool AncestryArrived(JsonObject payload, Dictionary<Guid, JsonObject> folders)
    {
        var value = Value(payload);
        JsonNode? next = payload["type"]!.GetValue<string>() switch
        { "folder" => value["parentID"], "tab" when value["placement"]!.GetValue<string>() != "pinned" => value["folderID"], _ => null };
        var seen = new HashSet<Guid>();
        while (next is not null)
        {
            var id = Id(next);
            if (!folders.TryGetValue(id, out var record)) return false;
            if (!seen.Add(id)) return true; // Materialization rejects cycles.
            if (Payload(record) is not { } folder) return false;
            next = Value(folder)["parentID"];
        }
        return true;
    }
    public byte[] Read() => encoded.Value;
    private byte[] Encode()
    {
        var value = metadata.DeepClone().AsObject();
        value["records"] = new JsonArray(records.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => p.Value.DeepClone()).ToArray());
        value["pendingRecordIDs"] = new JsonArray(pending.Order(StringComparer.Ordinal).Select(id => records[id]["id"]!.DeepClone()).ToArray());
        var result = Encoding.UTF8.GetBytes(value.ToJsonString());
        if (result.Length > MaximumBytes) throw new BrowserRuleException("sync_size_limit");
        return result;
    }
}
