using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Variables

    private const int MaximumSelectionCandidates = 3;

    #endregion

    #region Actions - Windows

    /// Null when the operation is not a window or tab-selection policy. Window
    /// state is device-local: these operations answer from identities and
    /// presence facts, and the native store applies the answer to its record.
    private static JsonObject? EvaluateWindows(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.WindowRepair: {
                    Protocol.Members(request, "version", "operation", "selectedSpaceID",
                        "capturesSelection", "spaces", "splitLayouts");
                    var spaces = new List<WindowSpaceFacts>();
                    foreach (var item in request.GetProperty("spaces").EnumerateArray()) {
                        if (spaces.Count >= WindowStatePolicy.MaximumSpaces) throw new BrowserRuleException(BrowserRuleCodes.WindowStateLimit);
                        Protocol.Members(item, "id", "windowTab", "captured", "hasTabs");
                        spaces.Add(new(Protocol.Id(item, "id"), item.GetProperty("windowTab").GetBoolean(),
                            item.GetProperty("captured").GetBoolean(), item.GetProperty("hasTabs").GetBoolean()));
                    }
                    var layouts = new List<WindowSplitLayout>();
                    foreach (var item in request.GetProperty("splitLayouts").EnumerateArray()) {
                        if (layouts.Count >= WindowStatePolicy.MaximumSplitLayouts) throw new BrowserRuleException(BrowserRuleCodes.WindowStateLimit);
                        Protocol.Members(item, "groupID", "columns", "liveMembers");
                        layouts.Add(new(Protocol.Id(item, "groupID"), item.GetProperty("columns").GetInt32(),
                            Optional(item, "liveMembers") is { } live ? live.GetInt32() : null));
                    }
                    var repair = WindowStatePolicy.Repair(Protocol.Id(request, "selectedSpaceID"),
                        request.GetProperty("capturesSelection").GetBoolean(), spaces, layouts);
                    return new() {
                        ["selectedSpaceID"] = repair.SelectedSpaceId.ToString("D"),
                        ["selections"] = new JsonArray(repair.Selections.Select(value => (JsonNode?)WindowCodes.Selection(value)).ToArray()),
                        ["splitLayouts"] = Ids(repair.SplitLayouts),
                        ["capturedSpaceIDs"] = repair.CapturedSpaceIds is { } captured ? Ids(captured) : null
                    };
                }
            case PolicyOperation.WindowSplitLayout: {
                    Protocol.Members(request, "version", "operation", "fractions");
                    var fractions = request.GetProperty("fractions").EnumerateArray().Take(BrowserTabCollection.MaximumSplitMembers + 1)
                        .Select(value => value.GetDouble()).ToArray();
                    var stored = WindowStatePolicy.SplitFractions(fractions);
                    return new() {
                        ["fractions"] = stored is null ? null : new JsonArray(stored.Select(value => (JsonNode?)JsonValue.Create(value)).ToArray())
                    };
                }
            case PolicyOperation.WindowTearOff: {
                    Protocol.Members(request, "version", "operation", "spaceMatches", "spaceLocked", "containsTab",
                        "selectionCount", "selectionIncludesTab");
                    int? count = Optional(request, "selectionCount") is { } value ? value.GetInt32() : null;
                    if (count < 0) throw new ProtocolException(ProtocolErrorCodes.InvalidLimit);
                    return new() {
                        ["allowed"] = WindowStatePolicy.AllowsTearOff(request.GetProperty("spaceMatches").GetBoolean(),
                            request.GetProperty("spaceLocked").GetBoolean(), request.GetProperty("containsTab").GetBoolean(),
                            count, request.GetProperty("selectionIncludesTab").GetBoolean())
                    };
                }
            case PolicyOperation.TabsSelectionFallback: {
                    Protocol.Members(request, "version", "operation", "placements");
                    var placements = new List<TabPlacement>();
                    foreach (var item in request.GetProperty("placements").EnumerateArray()) {
                        if (placements.Count >= MaximumSelectionCandidates) throw new ProtocolException(ProtocolErrorCodes.RecordBatchLimit);
                        placements.Add(TabPlacementCodes.Parse(item.GetString()) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPlacement));
                    }
                    return new() { ["index"] = TabSelectionPolicy.Fallback(placements) };
                }
            default:
                return null;
        }
    }

    private static JsonArray Ids(IEnumerable<Guid> values) =>
        new(values.Select(value => (JsonNode?)value.ToString("D")).ToArray());

    #endregion
}
