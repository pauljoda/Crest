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
        if (operation is "navigation.link" or "navigation.modified_link")
        {
            bool peek, newTab;
            if (operation == "navigation.modified_link")
            {
                Protocol.Members(request, "version", "operation", "url", "userActivatedLink", "topLevel",
                    "commandModified", "optionModified", "middleClick", "peekModifier", "shiftModified", "focusesNewTabs",
                    "hasContext", "placement", "savedUrl", "automaticallyOpensPeek");
                var preference = Protocol.Text(request, "peekModifier") switch {
                    "option" => LinkPeekModifier.Option, "command" => LinkPeekModifier.Command,
                    _ => throw new ProtocolException("invalid_peek_modifier")
                };
                (peek, newTab) = LinkNavigationPolicy.Modifiers(request.GetProperty("commandModified").GetBoolean(),
                    request.GetProperty("optionModified").GetBoolean(), request.GetProperty("middleClick").GetBoolean(), preference);
            }
            else
            {
                Protocol.Members(request, "version", "operation", "url", "userActivatedLink", "topLevel",
                    "peekModified", "newTabModified", "shiftModified", "focusesNewTabs", "hasContext",
                    "placement", "savedUrl", "automaticallyOpensPeek");
                peek = request.GetProperty("peekModified").GetBoolean();
                newTab = request.GetProperty("newTabModified").GetBoolean();
            }
            var decision = LinkNavigationPolicy.Decide(request.GetProperty("url").GetString(),
                request.GetProperty("userActivatedLink").GetBoolean(), request.GetProperty("topLevel").GetBoolean(),
                peek, newTab,
                request.GetProperty("shiftModified").GetBoolean(), request.GetProperty("focusesNewTabs").GetBoolean(),
                request.GetProperty("hasContext").GetBoolean(), request.GetProperty("placement").GetString(),
                request.GetProperty("savedUrl").GetString(), request.GetProperty("automaticallyOpensPeek").GetBoolean());
            return Encode(new() { ["decision"] = decision switch {
                LinkNavigationDecision.PeekModifier => "peekModifier", LinkNavigationDecision.PeekSavedSite => "peekSavedSite",
                LinkNavigationDecision.BackgroundTab => "backgroundTab", LinkNavigationDecision.ForegroundTab => "foregroundTab",
                _ => "navigate"
            }});
        }
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
        if (operation == "residency.release_limit")
        {
            Protocol.Members(request, "version", "operation", "level", "platform", "eligiblePageCount");
            return Encode(new() { ["limit"] = PageResidencyPolicy.ReleaseLimit(Level(request),
                request.GetProperty("eligiblePageCount").GetInt32(), Platform(request)) });
        }
        if (operation == "residency.release_plan")
        {
            Protocol.Members(request, "version", "operation", "level", "platform", "focusedIndex", "candidates");
            var candidates = new List<ResidencyCandidate>();
            foreach (var value in request.GetProperty("candidates").EnumerateArray())
            {
                Protocol.Members(value, "tabID", "inactiveSince", "keepsPageLoaded", "isPresented", "presentedIndex");
                candidates.Add(new(Protocol.Id(value, "tabID").ToString(),
                    Optional(value, "inactiveSince") is { } stamp ? stamp.GetDouble() : null,
                    Optional(value, "keepsPageLoaded")?.GetBoolean() ?? false,
                    Optional(value, "isPresented")?.GetBoolean() ?? false,
                    Optional(value, "presentedIndex") is { } index ? index.GetInt32() : null));
                if (candidates.Count > PageResidencyPolicy.MaximumCandidates)
                    throw new ProtocolException("residency_candidate_limit");
            }
            var plan = PageResidencyPolicy.ReleasePlan(candidates, Level(request), Platform(request),
                Optional(request, "focusedIndex") is { } focus ? focus.GetInt32() : null);
            return Encode(new() { ["tabIDs"] = Identifiers(plan.OffScreen), ["fallbackTabIDs"] = Identifiers(plan.PresentedFallback) });
        }
        if (operation == "residency.process_recovery")
        {
            Protocol.Members(request, "version", "operation", "consecutiveTerminations");
            var action = PageProcessRecoveryPolicy.Decide(request.GetProperty("consecutiveTerminations").GetInt32());
            return Encode(new() { ["action"] = action == ProcessRecoveryAction.Reload ? "reload" : "showFailure",
                ["maximumAutomaticReloads"] = PageProcessRecoveryPolicy.MaximumAutomaticReloads });
        }
        if (operation == "tabs.dismissal")
        {
            Protocol.Members(request, "version", "operation", "placement", "isStartPage", "tabCount");
            var placement = Optional(request, "placement") is null ? (TabPlacement?)null : Protocol.Text(request, "placement") switch
            {
                "current" => TabPlacement.Current, "pinned" => TabPlacement.Pinned, "saved" => TabPlacement.Saved,
                _ => throw new ProtocolException("invalid_placement")
            };
            var action = TabDismissalPolicy.Decide(placement,
                Optional(request, "isStartPage")?.GetBoolean() ?? false,
                request.GetProperty("tabCount").GetInt32());
            return Encode(new() { ["action"] = action switch {
                TabDismissalAction.UnloadPage => "unloadPage", TabDismissalAction.CloseTab => "closeTab",
                _ => "closeWindow"
            }});
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
    private static JsonElement? Optional(JsonElement value, string field) =>
        value.TryGetProperty(field, out var member) && member.ValueKind != JsonValueKind.Null ? member : null;
    private static JsonArray Identifiers(IReadOnlyList<string> values) =>
        new(values.Select(value => (JsonNode?)JsonValue.Create(value)).ToArray());
    private static MemoryPressureLevel Level(JsonElement request) => Protocol.Text(request, "level") switch
    {
        "warning" => MemoryPressureLevel.Warning, "critical" => MemoryPressureLevel.Critical,
        _ => throw new ProtocolException("invalid_pressure_level")
    };
    private static MemoryPressurePlatform Platform(JsonElement request) => Protocol.Text(request, "platform") switch
    {
        "desktop" => MemoryPressurePlatform.Desktop, "mobile" => MemoryPressurePlatform.Mobile,
        _ => throw new ProtocolException("invalid_pressure_platform")
    };
    private static DateTimeOffset Date(JsonElement value, string field)
    {
        double seconds = value.GetProperty(field).GetDouble();
        if (!double.IsFinite(seconds)) throw new ProtocolException("invalid_date");
        return DateTimeOffset.UnixEpoch.AddSeconds(seconds);
    }
}
