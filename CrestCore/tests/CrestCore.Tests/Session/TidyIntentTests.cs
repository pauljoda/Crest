using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Tidy files loose open tabs into groups it marks as its own, fills those
/// groups again on any device rather than making a second of the same name,
/// never fills a group a person made, and refuses any other tab without
/// changing anything.
public sealed partial class BrowserContractsTests {
    #region Actions - Tests

    /// Each topic becomes a group Tidy made, where its first tab was. A later
    /// Tidy fills that group, opening it, but makes its own group beside one a
    /// person made of the same name, and beside one that became a folder.
    [Fact]
    public void TidyFillsOnlyTheGroupsItMade() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Open));
        var opened = Opened(device, window, f.Space, 7);
        var personal = Guid.NewGuid();
        device.Send(new CreateFolder(device.Workspace, f.Space, personal, TabPlacement.Current, null, "Recipes",
            FolderState.DefaultColor, "folder", [opened[5]], LeavesSplits: false, IsGroup: true));

        device.Send(new TidyTabs(device.Workspace, f.Space, [new("Reading", [f.Open, f.Last]), new("Recipes", [opened[0], opened[1]])]));

        var space = core.Current.Spaces[0];
        var reading = Assert.Single(space.Folders, folder => folder.Title == "Reading");
        var recipes = Assert.Single(space.Folders, folder => folder.Title == "Recipes" && folder.Id != personal);
        Assert.All(new[] { reading, recipes }, made =>
            Assert.Equal((true, true, TabPlacement.Current, (Guid?)null), (made.IsGroup, made.MadeByTidy, made.Location, made.ParentId)));
        Assert.False(space.Folders.Single(folder => folder.Id == personal).MadeByTidy);
        Assert.Equal([f.Open, f.Last], Filed(space, reading.Id));
        Assert.Equal(new HashSet<Guid> { opened[0], opened[1] }, Filed(space, recipes.Id).ToHashSet());
        Assert.Equal([opened[5]], Filed(space, personal));

        device.Send(new CollapseFolder(device.Workspace, f.Space, reading.Id, true));
        device.Send(new SetFolderGroup(device.Workspace, f.Space, recipes.Id, IsGroup: false));
        device.Send(new TidyTabs(device.Workspace, f.Space, [new("reading", [opened[2], opened[3]])]));
        device.Send(new TidyTabs(device.Workspace, f.Space, [new("RECIPES", [opened[4], opened[6]])]));

        space = core.Current.Spaces[0];
        var refilled = Assert.Single(space.Folders, folder => folder.Id == reading.Id);
        Assert.Equal(("Reading", false), (refilled.Title, refilled.IsCollapsed));
        var refiled = Filed(space, reading.Id);
        Assert.Equal([f.Open, f.Last], refiled[..2]);
        Assert.Equal(new HashSet<Guid> { opened[2], opened[3] }, refiled[2..].ToHashSet());
        Assert.Equal([opened[5]], Filed(space, personal));
        var made = Assert.Single(space.Folders, folder => folder.Id != personal && folder.Id != recipes.Id && folder.Title == "RECIPES");
        Assert.True(made.MadeByTidy);
    }

    /// Tidy files only an open tab outside every folder, group and split, once
    /// each, in topics of two or more; anything else is refused and nothing
    /// changes.
    [Fact]
    public void TidyRefusesAnyTabThatIsNotLooseAndOpen() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Open));
        var loose = Opened(device, window, f.Space, 1)[0];
        var before = core.Current;

        foreach (var refused in new[] { f.Pinned, f.Saved, f.Left, f.Filed })
            Assert.IsType<TabCannotBeTidied>(Assert.Throws<Rejected>(() => device.Send(
                new TidyTabs(device.Workspace, f.Space, [new("Topic", [refused, loose])]))).Rejection);
        Assert.IsType<TabCannotBeTidied>(Assert.Throws<Rejected>(() => device.Send(new TidyTabs(device.Workspace, f.Space,
            [new("Topic", [f.Open, loose]), new("Other", [f.Last, loose])]))).Rejection);
        Assert.IsType<TidyTopicNeedsTwoTabs>(Assert.Throws<Rejected>(() => device.Send(
            new TidyTabs(device.Workspace, f.Space, [new("Topic", [f.Open, f.Last]), new("Alone", [loose])]))).Rejection);
        Assert.Same(before, core.Current);
    }

    /// A group Tidy makes on one device carries Tidy's mark in its record, so
    /// Tidy on another device fills it rather than making a second, and both
    /// devices end up with the one group holding every tab.
    [Fact]
    public void TidyOnAnotherDeviceFillsTheGroupTidyMadeHere() {
        var (space, first, second, third, fourth) = (Fixed(1_800), Fixed(1_801), Fixed(1_802), Fixed(1_803), Fixed(1_804));
        var start = SessionOf(SpaceOf(space, Fixed(1_805), tabs: [
            TabOf(first, "Pad thai", "https://example.com/pad-thai", activated: 500),
            TabOf(second, "Green curry", "https://example.com/green-curry", activated: 500),
            TabOf(third, "Tom yum", "https://example.org/tom-yum", activated: 500),
            TabOf(fourth, "Massaman", "https://example.org/massaman", activated: 500)
        ]));
        var merged = CloudHolding(start, 1_806);
        using var tidying = new SyncingDevice(start, merged(1_807));
        using var other = new SyncingDevice(start, merged(1_808));

        tidying.Edit(workspace => new TidyTabs(workspace, space, [new("Thai dishes", [first, second])]));
        var group = StoredSessionCodec.DecodeFolder(Assert.Single(SpaceIn(tidying.Session, space)!["folders"]!.AsArray())!).Id;
        Assert.True(tidying.Journal.Value(SyncRecordKind.Folder, group)!["madeByTidy"]!.GetValue<bool>());
        Settle(tidying, other);
        other.Edit(workspace => new TidyTabs(workspace, space, [new("thai dishes", [third, fourth])]));
        Settle(tidying, other);

        foreach (var device in new[] { tidying, other }) {
            var held = SpaceIn(device.Session, space)!;
            var folder = StoredSessionCodec.DecodeFolder(Assert.Single(held["folders"]!.AsArray())!);
            Assert.Equal((group, "Thai dishes", true, true), (folder.Id, folder.Title, folder.IsGroup, folder.MadeByTidy));
            Assert.Equal([first, second, third, fourth], held["tabs"]!.AsArray()
                .Where(tab => tab!["folderID"] is { } filed && StoredSessionCodec.Identity(filed) == group)
                .Select(tab => StoredSessionCodec.Identity(tab!["id"])));
        }
    }

    #endregion

    #region Actions - Fixtures

    /// Opens `count` web pages among the open tabs of `space` from `window`,
    /// each where a new tab goes.
    private static Guid[] Opened(TestDevice device, Guid window, Guid space, int count) {
        var tabs = Enumerable.Range(0, count).Select(_ => Guid.NewGuid()).ToArray();
        foreach (var (tab, index) in tabs.Select((tab, index) => (tab, index)))
            device.Send(new OpenTab(device.Workspace, window, space, tab,
                new TabContent($"https://example.org/{index}", null, $"Page {index}"), TabPlacement.Current, null, Shows: false));
        return tabs;
    }

    /// The tabs `folder` holds in `space`, in sidebar order.
    private static Guid[] Filed(SpaceState space, Guid folder) =>
        [.. space.Tabs.Where(tab => tab.FolderId == folder).Select(tab => tab.Id)];

    #endregion
}
