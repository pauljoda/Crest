using System.Text;
using System.Text.Json.Nodes;
using System.Text.Json;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Bounded, deterministic domain calls for existing synchronous native APIs.
/// This path owns no session, queue, engine, I/O, callback, or retained state.
public static class NativePolicyEvaluator
{
    public const int MaximumInputBytes = 16_384;
    public const int MaximumOutputBytes = 65_536;
    public static byte[] Evaluate(ReadOnlySpan<byte> utf8)
    {
        if (utf8.Length > MaximumInputBytes) throw new ProtocolException("policy_input_limit");
        var request = Protocol.Parse(utf8);
        if (request.GetProperty("version").GetInt32() != 1) throw new ProtocolException("version_mismatch");
        var operation = Protocol.Text(request, "operation");
        if (operation is "records.expired" or "history.remove_range")
        {
            Protocol.Members(request, operation == "records.expired"
                ? ["version", "operation", "timestamps", "now", "lifetime"]
                : ["version", "operation", "timestamps", "start", "end"]);
            var timestamps = request.GetProperty("timestamps").EnumerateArray().Select(value => value.GetDouble()).ToArray();
            if (timestamps.Length > 512) throw new ProtocolException("record_batch_limit");
            var indices = operation == "records.expired"
                ? RecordRemovalPolicy.Expired(timestamps, request.GetProperty("now").GetDouble(), request.GetProperty("lifetime").GetDouble())
                : RecordRemovalPolicy.WithinRange(timestamps, request.GetProperty("start").GetDouble(), request.GetProperty("end").GetDouble());
            return Encode(new() { ["indices"] = new JsonArray(indices.Select(index => (JsonNode?)JsonValue.Create(index)).ToArray()) });
        }
        if (operation == "history.normalize")
        {
            Protocol.Members(request, "version", "operation", "url");
            return Encode(new() { ["url"] = HistoryPolicy.Normalize(Protocol.Text(request, "url")) });
        }
        if (operation == "history.visit")
        {
            Protocol.Members(request, "version", "operation", "url", "title", "now", "newId", "previous");
            HistoryVisit? previous = null;
            if (request.TryGetProperty("previous", out var old) && old.ValueKind != JsonValueKind.Null)
            {
                Protocol.Members(old, "id", "url", "title", "firstVisitedAt", "lastVisitedAt", "visitCount");
                previous = new(Protocol.Id(old, "id"), Protocol.Text(old, "url"), old.GetProperty("title").GetString() ?? "",
                    Date(old, "firstVisitedAt"), Date(old, "lastVisitedAt"), old.GetProperty("visitCount").GetInt32());
                if (previous.VisitCount < 1) throw new ProtocolException("invalid_visit_count");
            }
            string? title = request.TryGetProperty("title", out var name) && name.ValueKind != JsonValueKind.Null ? name.GetString() : null;
            var visit = HistoryPolicy.Record(Protocol.Text(request, "url"), title, Date(request, "now"), Protocol.Id(request, "newId"), previous);
            return Encode(new()
            {
                ["entry"] = new JsonObject { ["id"] = visit.Id.ToString(), ["url"] = visit.Url, ["title"] = visit.Title,
                    ["firstVisitedAt"] = (visit.FirstVisitedAt - DateTimeOffset.UnixEpoch).TotalSeconds,
                    ["lastVisitedAt"] = (visit.VisitedAt - DateTimeOffset.UnixEpoch).TotalSeconds, ["visitCount"] = visit.VisitCount },
                ["maximumEntries"] = HistoryPolicy.MaximumEntries
            });
        }
        Protocol.Members(request, "version", "operation", "input", "searchTemplate", "allowsInternalPages");
        if (Protocol.Text(request, "operation") != "address.intent") throw new ProtocolException("unknown_policy");
        // An empty address is a successful no-navigation decision.
        var input = request.GetProperty("input").GetString() ?? throw new ProtocolException("invalid_input");
        var template = Protocol.Text(request, "searchTemplate", 2048);
        var provider = SearchProvider.Custom(Guid.Parse("00000000-0000-0000-0000-000000000001"), "Native provider", template, null);
        bool allowsInternalPages = request.TryGetProperty("allowsInternalPages", out var internalPages) && internalPages.GetBoolean();
        var intent = AddressResolution.Resolve(input, provider, allowsInternalPages);
        return Encode(new JsonObject
        {
            ["url"] = intent?.Url, ["searchQuery"] = intent?.SearchQuery
        });
    }
    private static byte[] Encode(JsonObject value) => Encoding.UTF8.GetBytes(value.ToJsonString());
    private static DateTimeOffset Date(JsonElement value, string field)
    {
        double seconds = value.GetProperty(field).GetDouble();
        if (!double.IsFinite(seconds)) throw new ProtocolException("invalid_date");
        return DateTimeOffset.UnixEpoch.AddSeconds(seconds);
    }
}
