using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class WorkspaceReviewTests {
    private static ImportReviewTab Tab(string? url, TabPlacement? placement = null) =>
        new(Guid.NewGuid(), url, placement ?? TabPlacement.Current);

    private static SpaceReview Choice(ImportReviewSpace source, Guid? destination, bool included = true,
        params TabPlacementChoice[] placements) =>
        new(source.Id, included, destination, new("Imported", "globe", SpaceAccent.Indigo, StoredSessionCodec.DecodeBranding(new JsonObject())),
            [.. source.Tabs.Select(tab => tab.Id)], placements);

    [Fact]
    public void ReviewMatchesFoldedSpaceNamesAndLeavesOutTabsTheDestinationHolds() {
        var existingTab = Tab("https://example.com/a#section");
        var existing = new ImportReviewSpace(Guid.NewGuid(), "Wörk", [existingTab]);
        var duplicate = Tab("https://example.com/a"); var fresh = Tab("https://example.com/b"); var native = Tab(null);
        var source = new ImportReviewSpace(Guid.NewGuid(), " work! ", [duplicate, fresh, native]);
        var unmatched = new ImportReviewSpace(Guid.NewGuid(), "!!!", [Tab("https://example.com/a")]);
        var suggestions = ImportReviewPolicy.Suggest([source, unmatched], [existing], false).Spaces;
        Assert.Equal(existing.Id, suggestions[0].DestinationId);
        Assert.Equal([duplicate.Id], suggestions[0].DuplicateTabIds);
        Assert.Equal([fresh.Id, native.Id], suggestions[0].IncludedTabIds);
        Assert.Null(suggestions[1].DestinationId);
        Assert.Null(ImportReviewPolicy.Suggest([source], [existing], true).Spaces[0].DestinationId);
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
            [Choice(source, existing.Id, placements: new TabPlacementChoice(promoted.Id, TabPlacement.Pinned)), Choice(fresh, null)]);
        Assert.Equal([second.Id, promoted.Id], analysis.OverflowTabIds);
        Assert.Equal([promoted.Id], analysis.Spaces[0].DuplicateTabIds);
        Assert.Equal([existing.Tabs[^1].Id], analysis.Spaces[0].MatchedTabIds);
        Assert.Empty(analysis.Spaces[1].DuplicateTabIds);
        var dropped = ImportReviewPolicy.Analyze([source], [existing], [Choice(source, existing.Id, included: false)]);
        Assert.Empty(dropped.OverflowTabIds);
        Assert.Empty(dropped.Spaces[0].MatchedTabIds);
        Assert.Equal([promoted.Id], dropped.Spaces[0].DuplicateTabIds);
    }

    [Fact]
    public void ImportsRejectSplitRunsThatRepairWouldRewrite() {
        Guid group = Guid.NewGuid(), folder = Guid.NewGuid();
        SplitMember Member(TabPlacement? placement = null, Guid? inFolder = null) => new(group, placement ?? TabPlacement.Current, inFolder);
        WorkspaceImportPolicy.RequireSplitMembership([Member(), Member(), new(null, TabPlacement.Current, null)]);
        WorkspaceImportPolicy.RequireSplitMembership([Member()]);
        Assert.Throws<Rejected>(() => WorkspaceImportPolicy.RequireSplitMembership([Member(), Member(TabPlacement.Saved)]));
        Assert.Throws<Rejected>(() => WorkspaceImportPolicy.RequireSplitMembership([Member(), Member(inFolder: folder)]));
        Assert.Throws<Rejected>(() => WorkspaceImportPolicy.RequireSplitMembership([Member(TabPlacement.Pinned)]));
        Assert.Throws<Rejected>(() => WorkspaceImportPolicy.RequireSplitMembership(
            Enumerable.Repeat(Member(), BrowserTabCollection.MaximumSplitMembers + 1).ToArray()));
        Assert.Throws<Rejected>(() => WorkspaceImportPolicy.RequireSplitMembership(
            [Member(), new(null, TabPlacement.Current, null), Member()]));
    }
}
