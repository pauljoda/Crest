using System.Text;
using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Maps the existing Swift/CloudKit wire records to engine-independent rules.
/// Unknown payload fields survive; no cloud API or page object crosses here.
public static class NativeSyncEvaluator
{
    public const int MaximumBytes = 16 * 1024 * 1024;
    public static byte[] Evaluate(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length is 0 or > MaximumBytes) throw new BrowserRuleException("sync_size_limit");
        var request = JsonNode.Parse(bytes, documentOptions: new() { MaxDepth = 64 })!.AsObject();
        if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException("version_mismatch");
        JsonNode result = request["operation"]!.GetValue<string>() switch
        {
            "resolve" => Resolve(request["first"]!.AsObject(), request["second"]!.AsObject()),
            "reconcile" => Reconcile(request["records"]!.AsArray().Select(n => n!.AsObject())),
            "order.allocate" => new JsonArray(SyncOrderTokens.Allocate(
                request["tokens"]!.AsArray().Select(n => n?.GetValue<string>()).ToArray())
                .Select(t => (JsonNode)JsonValue.Create(t)!).ToArray()),
            _ => throw new BrowserRuleException("unknown_sync_operation")
        };
        var output = Encoding.UTF8.GetBytes(result.ToJsonString());
        if (output.Length > MaximumBytes) throw new BrowserRuleException("sync_size_limit");
        return output;
    }

    private static string Text(JsonNode value, string field) => value[field]!.GetValue<string>();
    private static double? Date(JsonNode value, string field)
    {
        if (value[field] is null) return null;
        double date = value[field]!.GetValue<double>();
        if (!double.IsFinite(date)) throw new BrowserRuleException("invalid_sync_date");
        return date;
    }
    private static Guid Id(JsonNode? value) => NativeSessionAuthority.Id(value);
    private static SyncVersion Version(JsonNode value)
        => new(value["version"]!["logicalClock"]!.GetValue<ulong>(), Id(value["version"]!["deviceID"]));
    private static string Kind(JsonNode value) => Text(value["id"]!, "kind");
    private static string Name(JsonNode value) => Kind(value) + ":" + Id(value["id"]!["value"]).ToString("D");
    private static JsonObject? Payload(JsonNode value) => value["payload"]?["value"]?.AsObject();
    private static SyncRecordStamp Stamp(JsonNode record)
    {
        string kind = Kind(record);
        if (kind is not ("space" or "folder" or "tab" or "history" or "archive")) throw new BrowserRuleException("invalid_sync_kind");
        var payload = Payload(record);
        var tombstone = record["tombstone"];
        if ((payload is null) == (tombstone is null)) throw new BrowserRuleException("invalid_sync_record");
        if (payload is not null && Text(record["payload"]!, "type") != kind) throw new BrowserRuleException("sync_identity_mismatch");
        var recordId = Id(record["id"]!["value"]);
        var spaceId = Id(record["spaceID"]);
        if (kind == "space" && recordId != spaceId) throw new BrowserRuleException("sync_identity_mismatch");
        if (payload is not null)
        {
            var identity = kind == "archive" ? payload["tab"]! : payload;
            if (Id(identity["id"]) != recordId || (kind != "space" && Id(identity["spaceID"]) != spaceId))
                throw new BrowserRuleException("sync_identity_mismatch");
        }
        var reason = tombstone?["reason"]?.GetValue<string>();
        if (tombstone is not null && reason is not ("explicitDelete" or "superseded" or "retention"))
            throw new BrowserRuleException("invalid_sync_deletion");
        return new(kind, recordId, spaceId, Version(record), reason,
            tombstone is null ? null : Date(tombstone, "deletedAt"), kind == "tab" && payload is not null ? Date(payload, "lastActivatedAt") : null);
    }
    internal static void ValidateRecord(JsonObject record) => _ = Stamp(record);
    // Wire identities are UUID values, independent of the writer's letter case.
    // Keep ordinary strings (including UUID-looking titles) case-sensitive.
    // Codable also omits nil fields while the core may emit explicit JSON null.
    internal static bool Equivalent(JsonNode? first, JsonNode? second) => Equivalent(first, second, null);
    private static bool Equivalent(JsonNode? first, JsonNode? second, string? field)
    {
        if (first is JsonObject a && second is JsonObject b)
            return a.Select(p => p.Key).Union(b.Select(p => p.Key)).All(key =>
                Equivalent(a[key], b[key], key == "value" && a["kind"] is not null ? "id" : key));
        if (first is JsonArray x && second is JsonArray y)
            return x.Count == y.Count && x.Zip(y).All(pair => Equivalent(pair.First, pair.Second, field));
        bool identity = field is "id" or "rawValue" or "profileID" or "spaceID" or "deviceID"
            or "folderID" or "parentID" or "orderAnchorTabID" or "splitGroupID";
        if (identity && first is JsonValue av && second is JsonValue bv
            && av.TryGetValue<string>(out var at) && bv.TryGetValue<string>(out var bt)
            && Guid.TryParse(at, out var aid) && Guid.TryParse(bt, out var bid)) return aid == bid;
        // JSONEncoder and JSONSerialization can spell the same binary Date
        // differently (811615335.98 vs 811615335.98000002). Compare timestamp
        // values exactly as doubles, without rounding away real edits. Clocks
        // and other integer fields must retain their full integer precision.
        bool timestamp = field is "lastActivatedAt" or "positionModifiedAt" or "titleModifiedAt"
            or "savedTabsExpansionModifiedAt" or "collapseModifiedAt" or "iconModifiedAt" or "tintModifiedAt"
            or "archivedAt" or "deletedAt" or "firstVisitedAt" or "lastVisitedAt";
        if (timestamp && first is JsonValue ad && second is JsonValue bd
            && ad.TryGetValue<double>(out var aDate) && bd.TryGetValue<double>(out var bDate)) return aDate == bDate;
        return JsonNode.DeepEquals(first, second);
    }
    private static TabPlacement Placement(JsonNode payload) => Text(payload, "placement") switch
    {
        "pinned" => TabPlacement.Pinned, "saved" => TabPlacement.Saved, "current" => TabPlacement.Current,
        _ => throw new BrowserRuleException("invalid_sync_placement")
    };
    private static void Copy(JsonObject to, JsonObject from, params string[] fields)
    {
        foreach (string field in fields)
        {
            if (from.TryGetPropertyValue(field, out var value)) to[field] = value?.DeepClone();
            else to.Remove(field);
        }
    }
    private static void LatestFields(JsonObject result, JsonObject first, JsonObject second, string timestamp, params string[] fields)
    {
        if (SyncConflictPolicy.Latest(Date(first, timestamp), Date(second, timestamp)) is not { } winner) return;
        var source = winner == 0 ? first : second;
        Copy(result, source, fields);
        Copy(result, source, timestamp);
    }

    public static JsonObject Resolve(JsonObject first, JsonObject second)
    {
        var aStamp = Stamp(first); var bStamp = Stamp(second);
        int winner = SyncConflictPolicy.Winner(aStamp, bStamp);
        var result = (winner == 0 ? first : second).DeepClone().AsObject();
        var a = Payload(first); var b = Payload(second);
        if (a is null || b is null) return result;
        var payload = Payload(result)!;
        switch (aStamp.Kind)
        {
            case "space":
                LatestFields(payload, a, b, "savedTabsExpansionModifiedAt", "isSavedTabsExpanded");
                payload["splitGroups"] = MergeGroups(a["splitGroups"] as JsonArray, b["splitGroups"] as JsonArray, winner);
                break;
            case "folder":
                LatestFields(payload, a, b, "collapseModifiedAt", "isCollapsed");
                break;
            case "tab":
                payload["lastActivatedAt"] = Math.Max(Date(a, "lastActivatedAt")!.Value, Date(b, "lastActivatedAt")!.Value);
                if (SyncConflictPolicy.Latest(Date(a, "positionModifiedAt"), Date(b, "positionModifiedAt")) is { } position)
                {
                    var source = position == 0 ? a : b;
                    Copy(payload, source, "placement", "folderID", "orderToken", "positionModifiedAt", "splitGroupID");
                    if (Placement(source) == TabPlacement.Pinned) { payload.Remove("folderID"); payload.Remove("splitGroupID"); }
                }
                else
                {
                    var placement = SyncConflictPolicy.RetainedPlacement(Placement(a), Placement(b));
                    payload["placement"] = placement.ToString().ToLowerInvariant();
                    if (placement == TabPlacement.Pinned) payload.Remove("folderID");
                    else payload["folderID"] ??= (a["folderID"] ?? b["folderID"])?.DeepClone();
                    payload["splitGroupID"] ??= (a["splitGroupID"] ?? b["splitGroupID"])?.DeepClone();
                }
                LatestFields(payload, a, b, "titleModifiedAt", "customTitle");
                break;
            case "history":
                payload["firstVisitedAt"] = Math.Min(Date(a, "firstVisitedAt")!.Value, Date(b, "firstVisitedAt")!.Value);
                payload["lastVisitedAt"] = Math.Max(Date(a, "lastVisitedAt")!.Value, Date(b, "lastVisitedAt")!.Value);
                payload["visitCount"] = Math.Max(a["visitCount"]!.GetValue<int>(), b["visitCount"]!.GetValue<int>());
                break;
        }
        return result;
    }

    private static JsonNode? MergeGroups(JsonArray? first, JsonArray? second, int winner)
    {
        if (first is null || second is null) return (first ?? second)?.DeepClone();
        var preferred = winner == 0 ? first : second;
        var fallback = (winner == 0 ? second : first).ToDictionary(n => Id(n!["id"]), n => n!.AsObject());
        return new JsonArray(preferred.Select(n =>
        {
            var group = n!.DeepClone().AsObject();
            if (fallback.TryGetValue(Id(group["id"]), out var older))
            {
                LatestFields(group, n.AsObject(), older, "titleModifiedAt", "customTitle");
                LatestFields(group, n.AsObject(), older, "iconModifiedAt", "customIconSymbol");
                LatestFields(group, n.AsObject(), older, "tintModifiedAt", "tint");
            }
            return (JsonNode)group;
        }).ToArray());
    }

    internal static JsonArray Reconcile(IEnumerable<JsonObject> records)
    {
        var byId = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
        foreach (var node in records) { _ = Stamp(node!); byId[Name(node!)] = node!.AsObject(); }
        foreach (var tab in byId.Values.Where(r => Kind(r) == "tab" && Payload(r) is not null).ToArray())
        {
            string archiveName = "archive:" + Id(tab["id"]!["value"]).ToString("D");
            if (!byId.TryGetValue(archiveName, out var archiveRecord) || Payload(archiveRecord) is not { } archive) continue;
            var payload = Payload(tab)!;
            bool active = SyncConflictPolicy.ActiveTabWins(Placement(payload), Date(payload, "lastActivatedAt")!.Value,
                Version(tab), Text(archive, "reason"), Date(archive, "archivedAt")!.Value, Version(archiveRecord));
            byId.Remove(active ? archiveName : Name(tab));
        }
        return new JsonArray(byId.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => p.Value.DeepClone()).ToArray());
    }
}
