using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class OrganizationContractsTests {
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-19T12:00:00Z");
    private static FolderId FolderId() => new(Guid.NewGuid());
    private static BrowserSpace Space() => new(new(Guid.NewGuid()), new(Guid.NewGuid()), "Organization");
    private static BrowserTab Tab(BrowserSpace space, string name, Guid? split = null) {
        var state = new TabState(new(Guid.NewGuid()), TabContent.Web, $"https://example.com/{name}", name,
            TabPlacement.Current, null, null, null, Now, null, null, false, split);
        var tab = BrowserTab.Restore(state); space.Add(tab, null); return tab;
    }
    [Fact]
    public void FilingMovesWholeSplitsAndFolderSubtreesKeepTheirIdentities() {
        var space = Space(); var split = Guid.NewGuid(); var first = Tab(space, "first", split); var second = Tab(space, "second", split);
        var root = FolderId(); var child = FolderId(); var destination = FolderId();
        space.AddFolder(root, "Root", TabPlacement.Current); space.AddFolder(child, "Child", parent: root);
        space.AddFolder(destination, "Saved", TabPlacement.Saved);
        space.FileTabs([first.Id], TabPlacement.Current, child, Now);
        Assert.All(space.Tabs, t => { Assert.Equal(child, t.FolderId); Assert.Equal(split, t.SplitGroupId); });
        space.MoveFolder(root, null, destination, Now.AddMinutes(1));
        Assert.Equal(new[] { destination, root, child }, space.Folders.Select(f => f.Id));
        Assert.Equal(destination, space.Folders[1].ParentId);
        Assert.All(space.Folders, f => Assert.Equal(TabPlacement.Saved, f.Location));
        Assert.All(space.Tabs, t => { Assert.Equal(TabPlacement.Saved, t.Placement); Assert.Equal(t.Url, t.SavedUrl); Assert.Equal(split, t.SplitGroupId); });
        Assert.Equal(new[] { first.Id, second.Id }, space.Tabs.Select(t => t.Id));
    }
    [Fact]
    public void RemovingFolderPromotesContentsAndPreservesCollapseClock() {
        var space = Space(); var tab = Tab(space, "page"); var root = FolderId(); var folder = FolderId(); var child = FolderId();
        space.AddFolder(root, "Root"); space.AddFolder(folder, "Folder", parent: root); space.AddFolder(child, "Child", parent: folder);
        space.FileTabs([tab.Id], TabPlacement.Saved, folder, Now); space.CollapseFolder(child, true, Now);
        space.DeleteFolder(folder, Now.AddMinutes(1));
        Assert.Equal(root, tab.FolderId); Assert.Equal(root, space.Folders.Single(f => f.Id == child).ParentId);
        var saved = BrowserSpace.Restore(space.Capture(null));
        Assert.Equal(Now, saved.Folders.Single(f => f.Id == child).CollapseModifiedAt);
        Assert.Equal(tab.Id, Assert.Single(saved.Tabs).Id); Assert.Equal(tab.Url, saved.Tabs[0].SavedUrl);
        Assert.Empty(space.Archive);
    }
    [Fact]
    public void InvalidFolderMovesLeaveTopologyAndMembershipUntouched() {
        var space = Space(); var tab = Tab(space, "page"); var root = FolderId(); var child = FolderId();
        space.AddFolder(root, "Root"); space.AddFolder(child, "Child", parent: root);
        space.FileTabs([tab.Id], TabPlacement.Saved, child, Now);
        var original = space.Folders.ToArray(); var tabState = tab.Capture();
        Assert.Equal("folder_cycle", Assert.Throws<BrowserRuleException>(() => space.MoveFolder(root, null, child, Now)).Code);
        Assert.Equal(original, space.Folders); Assert.Equal(tabState, tab.Capture());
        var deepest = child;
        for (int depth = 2; depth < FolderTree.MaximumDepth; depth++) { var next = FolderId(); space.AddFolder(next, depth.ToString(), parent: deepest); deepest = next; }
        Assert.Equal("folder_depth_limit", Assert.Throws<BrowserRuleException>(() => space.AddFolder(FolderId(), "Too deep", parent: deepest)).Code);
        Assert.Equal(FolderTree.MaximumDepth, space.Folders.Count);
    }
    [Fact]
    public void InsertionCannotSplitAnExistingPairAndExplicitDetachRepairsTheSurvivor() {
        var space = Space(); var split = Guid.NewGuid(); var first = Tab(space, "first", split); var second = Tab(space, "second", split);
        var third = Tab(space, "third"); var folder = FolderId(); space.AddFolder(folder, "Destination", TabPlacement.Current);
        Assert.Equal("split_boundary", Assert.Throws<BrowserRuleException>(() =>
            space.FileTabs([third.Id], TabPlacement.Current, null, Now, before: second.Id)).Code);
        Assert.Equal(new[] { first.Id, second.Id, third.Id }, space.Tabs.Select(t => t.Id));
        space.FileTabs([first.Id], TabPlacement.Current, folder, Now, detachSplitMembers: true);
        Assert.Null(first.SplitGroupId); Assert.Null(second.SplitGroupId); Assert.Equal(folder, first.FolderId); Assert.Null(second.FolderId);
    }
    [Fact]
    public void EmptyFolderBoundarySurvivesClosingItsLastTab() {
        var space = Space(); var first = Tab(space, "first"); var last = Tab(space, "last"); var folder = FolderId();
        space.AddFolder(folder, "Current", TabPlacement.Current); space.FileTabs([first.Id], TabPlacement.Current, folder, Now);
        space.Remove(first, Now, true);
        Assert.Equal(last.Id, Assert.Single(space.Folders).OrderAnchorTabId);
        var restored = BrowserSpace.Restore(space.Capture(null));
        Assert.Equal(last.Id, new FolderTree(restored.Folders).TabAnchor(folder, restored.Tabs));
        Assert.Single(restored.Archive);
    }
}
