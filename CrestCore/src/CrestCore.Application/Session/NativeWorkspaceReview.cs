using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The review a person edits before a reviewed import. It reads whole Spaces
/// (addresses, placements and identities only), so it runs on the workspace
/// query path beside the preview it prepares, not the bounded policy path.
public static class NativeWorkspaceReview {
    #region Actions - Workspace review

    /// Without <c>choices</c>, the starting review per imported Space. With
    /// them, what those choices mean: duplicates and matched tabs per Space,
    /// and pinned tabs past their destination's limit.
    public static JsonObject Evaluate(JsonObject request) {
        var existing = Spaces(request["existing"]);
        var sources = Spaces(request["sources"]);
        if (request["choices"] is not JsonArray choices) {
            var suggestions = ImportReviewPolicy.Suggest(sources, existing,
                request["replacesDisposableSeed"]?.GetValue<bool>() ?? false);
            return new() {
                ["suggestions"] = new JsonArray(suggestions.Select(suggestion => (JsonNode?)new JsonObject {
                    ["destinationID"] = suggestion.DestinationId?.ToString("D"),
                    ["duplicateTabIDs"] = Ids(suggestion.DuplicateTabIds),
                    ["includedTabIDs"] = Ids(suggestion.IncludedTabIds)
                }).ToArray())
            };
        }
        var analysis = ImportReviewPolicy.Analyze(sources, existing, choices.Select(Choice).ToArray());
        return new() {
            ["duplicateTabIDs"] = new JsonArray(analysis.DuplicateTabIds.Select(ids => (JsonNode?)Ids(ids)).ToArray()),
            ["matchedTabIDs"] = new JsonArray(analysis.MatchedDestinationTabIds.Select(ids => (JsonNode?)Ids(ids)).ToArray()),
            ["overflowTabIDs"] = Ids(analysis.OverflowTabIds)
        };
    }

    private static ImportReviewSpace[] Spaces(JsonNode? value) =>
        (value as JsonArray ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedState)).Select(node => {
            var space = node!.AsObject();
            return new ImportReviewSpace(NativeSessionAuthority.Id(space["id"]), space["name"]?.GetValue<string>() ?? "",
                NativeSyncProjection.Items(space, StoredSessionCodec.Key.Tabs).Select(tab => new ImportReviewTab(NativeSessionAuthority.Id(tab!["id"]),
                    tab["url"]?.GetValue<string>(), Placement(tab["placement"]))).ToArray());
        }).ToArray();

    private static ImportReviewChoice Choice(JsonNode? node) {
        var choice = node!.AsObject();
        var placements = new Dictionary<Guid, TabPlacement>();
        foreach (var item in NativeSyncProjection.Items(choice, "placements"))
            placements[NativeSessionAuthority.Id(item!["tabID"])] = Placement(item["placement"]);
        return new(choice["included"]!.GetValue<bool>(),
            choice["destinationID"] is { } destination ? NativeSessionAuthority.Id(destination) : null,
            NativeSyncProjection.Items(choice, "includedTabIDs").Select(NativeSessionAuthority.Id).ToHashSet(), placements);
    }

    private static TabPlacement Placement(JsonNode? value) =>
        TabPlacement.Named(value?.GetValue<string>()) ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidPlacement);

    private static JsonArray Ids(IEnumerable<Guid> values) =>
        new(values.Select(value => (JsonNode?)value.ToString("D")).ToArray());

    #endregion
}
