using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class WorkspaceReviewTests {
    private static ImportReviewTab Tab(string? url, TabPlacement? placement = null) =>
        new(Guid.NewGuid(), url, placement ?? TabPlacement.Current);

    private static ImportReviewChoice Choice(ImportReviewSpace source, Guid? destination, bool included = true,
        IReadOnlyDictionary<Guid, TabPlacement>? placements = null) =>
        new(included, destination, source.Tabs.Select(tab => tab.Id).ToHashSet(), placements ?? new Dictionary<Guid, TabPlacement>());

    [Fact]
    public void ReviewMatchesFoldedSpaceNamesAndLeavesOutTabsTheDestinationHolds() {
        var existingTab = Tab("https://example.com/a#section");
        var existing = new ImportReviewSpace(Guid.NewGuid(), "Wörk", [existingTab]);
        var duplicate = Tab("https://example.com/a"); var fresh = Tab("https://example.com/b"); var native = Tab(null);
        var source = new ImportReviewSpace(Guid.NewGuid(), " work! ", [duplicate, fresh, native]);
        var unmatched = new ImportReviewSpace(Guid.NewGuid(), "!!!", [Tab("https://example.com/a")]);
        var suggestions = ImportReviewPolicy.Suggest([source, unmatched], [existing], false);
        Assert.Equal(existing.Id, suggestions[0].DestinationId);
        Assert.Equal([duplicate.Id], suggestions[0].DuplicateTabIds);
        Assert.Equal([fresh.Id, native.Id], suggestions[0].IncludedTabIds);
        Assert.Null(suggestions[1].DestinationId);
        Assert.Null(ImportReviewPolicy.Suggest([source], [existing], true)[0].DestinationId);
    }

    [Fact]
    public void AnalysisFlagsPinnedOverflowPerDestinationAndMatchesOnlyIncludedSpaces() {
        var pinnedTabs = Enumerable.Range(0, 11).Select(index => Tab($"https://pinned.example/{index}", TabPlacement.Pinned)).ToArray();
        var existing = new ImportReviewSpace(Guid.NewGuid(), "Work", [.. pinnedTabs, Tab("https://example.com/a")]);
        var first = Tab("https://one.example", TabPlacement.Pinned); var second = Tab("https://two.example", TabPlacement.Pinned);
        var promoted = Tab("https://example.com/a");
        var source = new ImportReviewSpace(Guid.NewGuid(), "Work", [first, second, promoted]);
        var fresh = new ImportReviewSpace(Guid.NewGuid(), "New", [Tab("https://three.example", TabPlacement.Pinned)]);
        var analysis = ImportReviewPolicy.Analyze([source, fresh], [existing],
            [Choice(source, existing.Id, placements: new Dictionary<Guid, TabPlacement> { [promoted.Id] = TabPlacement.Pinned }), Choice(fresh, null)]);
        Assert.Equal([second.Id, promoted.Id], analysis.OverflowTabIds);
        Assert.Equal([promoted.Id], analysis.DuplicateTabIds[0]);
        Assert.Equal([existing.Tabs[^1].Id], analysis.MatchedDestinationTabIds[0]);
        Assert.Empty(analysis.DuplicateTabIds[1]);
        var dropped = ImportReviewPolicy.Analyze([source], [existing], [Choice(source, existing.Id, included: false)]);
        Assert.Empty(dropped.OverflowTabIds);
        Assert.Empty(dropped.MatchedDestinationTabIds[0]);
        Assert.Equal([promoted.Id], dropped.DuplicateTabIds[0]);
    }

    [Fact]
    public void TheReviewQueryReadsWholeSpacesOnTheWorkspacePath() {
        var id = Guid.NewGuid(); var tab = Guid.NewGuid();
        JsonObject Space(Guid space, string name, Guid tabId) => new() {
            ["id"] = space.ToString("D"),
            ["name"] = name,
            ["tabs"] = new JsonArray(new JsonObject { ["id"] = tabId.ToString("D"), ["url"] = "https://example.com/", ["placement"] = "current" })
        };
        var request = new JsonObject {
            ["version"] = 1,
            ["operation"] = "workspace.review",
            ["replacesDisposableSeed"] = false,
            ["existing"] = new JsonArray(Space(id, "Home", Guid.NewGuid())),
            ["sources"] = new JsonArray(Space(Guid.NewGuid(), "home", tab)),
            ["choices"] = null
        };
        var value = JsonNode.Parse(NativeSyncQuery.Prepare(Encoding.UTF8.GetBytes(request.ToJsonString())))!["value"]!;
        Assert.Equal(id.ToString("D"), value["suggestions"]![0]!["destinationID"]!.GetValue<string>());
        Assert.Equal(tab.ToString("D"), value["suggestions"]![0]!["duplicateTabIDs"]![0]!.GetValue<string>());
    }

    [Fact]
    public void ImportsRejectSplitRunsThatRepairWouldRewrite() {
        Guid group = Guid.NewGuid(), folder = Guid.NewGuid();
        SplitMember Member(TabPlacement? placement = null, Guid? inFolder = null) => new(group, placement ?? TabPlacement.Current, inFolder);
        WorkspaceImportPolicy.RequireSplitMembership([Member(), Member(), new(null, TabPlacement.Current, null)]);
        WorkspaceImportPolicy.RequireSplitMembership([Member()]);
        Assert.Throws<BrowserRuleException>(() => WorkspaceImportPolicy.RequireSplitMembership([Member(), Member(TabPlacement.Saved)]));
        Assert.Throws<BrowserRuleException>(() => WorkspaceImportPolicy.RequireSplitMembership([Member(), Member(inFolder: folder)]));
        Assert.Throws<BrowserRuleException>(() => WorkspaceImportPolicy.RequireSplitMembership([Member(TabPlacement.Pinned)]));
        Assert.Throws<BrowserRuleException>(() => WorkspaceImportPolicy.RequireSplitMembership(
            Enumerable.Repeat(Member(), BrowserTabCollection.MaximumSplitMembers + 1).ToArray()));
        Assert.Throws<BrowserRuleException>(() => WorkspaceImportPolicy.RequireSplitMembership(
            [Member(), new(null, TabPlacement.Current, null), Member()]));
    }

    [Fact]
    public void APortableImportWithAMalformedSplitIsRejectedBeforeRepair() {
        static JsonObject Id(Guid value) => new() { ["rawValue"] = value.ToString("D") };
        var group = Guid.NewGuid();
        JsonObject Tab(string placement) => new() {
            ["id"] = Id(Guid.NewGuid()),
            ["title"] = "Page",
            ["url"] = "https://example.com/",
            ["placement"] = placement,
            ["splitGroupID"] = Id(group),
            ["lastActivatedAt"] = 1.0
        };
        var session = new JsonObject {
            ["spaces"] = new JsonArray(),
            ["selectedSpaceID"] = Id(Guid.NewGuid())
        };
        var source = new JsonObject {
            ["id"] = Id(Guid.NewGuid()),
            ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString("D") },
            ["name"] = "Archive",
            ["symbol"] = "book",
            ["accent"] = "indigo",
            ["tabs"] = new JsonArray(Tab("current"), Tab("saved")),
            ["folders"] = new JsonArray(),
            ["archivedTabs"] = new JsonArray(),
            ["history"] = new JsonArray()
        };
        var result = NativeWorkspaceImport.Preview(session, new JsonObject { ["sources"] = new JsonArray(source) }, "portable", 1.0);
        Assert.Equal(BrowserRuleCodes.InvalidSplit, result["error"]!.GetValue<string>());
    }
}
