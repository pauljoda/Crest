using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Opening, closing, deleting, clearing, copying and moving tabs: where a tab
/// lands, what its section refuses, what closing keeps, and which tab a window
/// shows afterwards.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ClosingArchivesAnOpenTabAndPutsASavedTabsPageAwayReturningTheWindowToItsPreviousTab() {
        using var device = new TestDevice(MaximalDocument());
        var core = device.Authority;
        TestGrants.UnlockGuarded(device.Send, device.Workspace, core.Current);
        var space = core.Current.Spaces[0];
        Guid Id(string value) => Guid.Parse(value);
        Guid left = Id("428CAA9C-9A7A-4386-B120-F6096032C167"), right = Id("942AC076-B0D8-454B-9EEB-3791E6113F77"),
            article = Id("B61250D4-3D4E-4DD6-8871-0BB326669142"), start = Id("056F15C0-13CE-4ED0-B9FE-DD4A9D05A56D");
        var window = device.Open(space.Id);
        foreach (var tab in new[] { start, right, article }) device.Send(new ShowTab(window, space.Id, tab));

        // A saved tab keeps its place, and its page returns to its saved
        // address when the app's preferences say so. The window that asked
        // lets the tab's page go, keeping nothing of it.
        var putAway = device.Send(new CloseTab(device.Workspace, window, space.Id, article)).OfType<TabPagePutAway>();
        var kept = core.Current.Spaces[0].Tabs.Single(tab => tab.Id == article);
        Assert.Equal((TabPlacement.Saved, "https://news.example/article"), (kept.Placement, kept.Url));
        Assert.Equal(right, device.Tab(window, space.Id));
        Assert.Equal([new TabPagePutAway(device.Workspace, window, space.Id, article, KeepsState: false)], putAway);

        // An open tab is archived, and the window goes back to the tab it
        // showed before; no page is put away.
        Assert.Empty(device.Send(new CloseTab(device.Workspace, window, space.Id, right)).OfType<TabPagePutAway>());
        Assert.DoesNotContain(core.Current.Spaces[0].Tabs, tab => tab.Id == right);
        var archived = core.Current.Spaces[0].ArchivedTabs[^1];
        Assert.Equal((right, ArchiveReason.Closed), (archived.Tab.Id, archived.Reason));
        Assert.Null(archived.Tab.SplitGroupId);
        Assert.Equal(start, device.Tab(window, space.Id));
        // Its split partner is left on its own, so the split and its name go.
        Assert.Null(core.Current.Spaces[0].Tabs.Single(tab => tab.Id == left).SplitGroupId);
        Assert.Empty(core.Current.Spaces[0].SplitGroups);
    }

    [Fact]
    public void ClosingTheOnlyTabAWindowShowedShowsTheTabBesideIt() {
        var fixture = new BatchSpace();
        using var device = new TestDevice(fixture.Session);

        // A window that has shown nothing else in the Space, as after a
        // relaunch, shows the tab below the one it closed rather than none,
        // and the other side of a split it closed one side of.
        var window = device.Open(fixture.Space, (fixture.Space, fixture.Open));
        device.Send(new CloseTab(device.Workspace, window, fixture.Space, fixture.Open));
        Assert.Equal(fixture.Left, device.Tab(window, fixture.Space));
        device.Send(new CloseTab(device.Workspace, window, fixture.Space, fixture.Left));
        Assert.Equal(fixture.Right, device.Tab(window, fixture.Space));

        // A tab the window showed before still comes first.
        device.Send(new ShowTab(window, fixture.Space, fixture.Pinned));
        device.Send(new ShowTab(window, fixture.Space, fixture.Last));
        device.Send(new CloseTab(device.Workspace, window, fixture.Space, fixture.Last));
        Assert.Equal(fixture.Pinned, device.Tab(window, fixture.Space));
    }

    [Fact]
    public void ClosingATabOpenedBehindWalksTheTabsOpenedWithItBeforeReturning() {
        var fixture = new BatchSpace();
        using var device = new TestDevice(fixture.Session);
        var window = device.Open(fixture.Space, (fixture.Space, fixture.Open));
        Guid Behind() {
            var id = Guid.NewGuid();
            device.Send(new OpenTab(device.Workspace, window, fixture.Space, id, new TabContent($"https://behind.example/{id}",
                View: null, Title: null), TabPlacement.Current, AfterTabId: fixture.Pinned, Shows: false, PlacesAsNewTab: true));
            return id;
        }

        // Three links opened behind the pinned tab, then the first one read:
        // closing walks to the next one the window has not shown, then the
        // last, and only then back to the pinned tab.
        device.Send(new ShowTab(window, fixture.Space, fixture.Pinned));
        Guid first = Behind(), second = Behind(), third = Behind();
        device.Send(new ShowTab(window, fixture.Space, first));
        device.Send(new CloseTab(device.Workspace, window, fixture.Space, first));
        Assert.Equal(second, device.Tab(window, fixture.Space));
        device.Send(new CloseTab(device.Workspace, window, fixture.Space, second));
        Assert.Equal(third, device.Tab(window, fixture.Space));
        device.Send(new CloseTab(device.Workspace, window, fixture.Space, third));
        Assert.Equal(fixture.Pinned, device.Tab(window, fixture.Space));

        // One shown after another goes back to the one shown before.
        Guid left = Behind(), right = Behind();
        device.Send(new ShowTab(window, fixture.Space, left));
        device.Send(new ShowTab(window, fixture.Space, right));
        device.Send(new CloseTab(device.Workspace, window, fixture.Space, right));
        Assert.Equal(left, device.Tab(window, fixture.Space));

        // A tab the window showed as the other side of a split was on screen,
        // even once it leaves the split, so closing returns to the pinned tab.
        device.Send(new ShowTab(window, fixture.Space, fixture.Pinned));
        Guid shownSide = Behind(), otherSide = Behind(), last = Behind();
        device.Send(new JoinSplit(device.Workspace, device.Open(fixture.Space), fixture.Space, otherSide, shownSide, null));
        device.Send(new ShowTab(window, fixture.Space, shownSide));
        device.Send(new ShowTab(window, fixture.Space, fixture.Pinned));
        device.Send(new LeaveSplit(device.Workspace, fixture.Space, otherSide));
        device.Send(new ShowTab(window, fixture.Space, last));
        device.Send(new CloseTab(device.Workspace, window, fixture.Space, last));
        Assert.Equal(fixture.Pinned, device.Tab(window, fixture.Space));
    }

    [Fact]
    public void PuttingAwaySavedTabsTogetherReturnsTheWindowToATabOutsideThem() {
        using var device = new TestDevice(MaximalDocument());
        var core = device.Authority;
        TestGrants.UnlockGuarded(device.Send, device.Workspace, core.Current);
        var space = core.Current.Spaces[0];
        Guid Id(string value) => Guid.Parse(value);
        Guid pinned = Id("853D3F20-BB2C-45F0-98BD-CCC71C646370"), article = Id("B61250D4-3D4E-4DD6-8871-0BB326669142"),
            start = Id("056F15C0-13CE-4ED0-B9FE-DD4A9D05A56D");
        var window = device.Open(space.Id);
        foreach (var tab in new[] { start, pinned, article }) device.Send(new ShowTab(window, space.Id, tab));

        // Closing them one by one would show the pinned tab again once the
        // shown article closed; together, the window goes back past both, and
        // each page is put away.
        var putAway = device.Send(new PutAwayTabs(device.Workspace, window, space.Id, [pinned, article]))
            .OfType<TabPagePutAway>().Select(change => change.TabId);
        Assert.Equal(start, device.Tab(window, space.Id));
        Assert.Equal([pinned, article], putAway.Order());
        Assert.All([pinned, article], id => Assert.Contains(core.Current.Spaces[0].Tabs, tab => tab.Id == id));

        // The window's history forgets both, so closing the tab it went back
        // to brings neither back.
        device.Send(new CloseTab(device.Workspace, window, space.Id, start));
        Assert.DoesNotContain(device.Tab(window, space.Id), new Guid?[] { pinned, article });
    }

    /// A Space with no pinned tab whose first saved tab and first open tab
    /// each sit in a collapsed folder, ahead of a loose saved tab and two
    /// loose open tabs.
    private sealed class CollapsedFoldersSpace {
        public Guid Space { get; } = Guid.NewGuid();
        public Guid SavedFolder { get; } = Guid.NewGuid();
        public Guid SavedInFolder { get; } = Guid.NewGuid();
        public Guid LooseSaved { get; } = Guid.NewGuid();
        public Guid OpenInFolder { get; } = Guid.NewGuid();
        public Guid Shown { get; } = Guid.NewGuid();
        public Guid NextOpen { get; } = Guid.NewGuid();
        public JsonNode Session { get; }

        public CollapsedFoldersSpace() {
            var openFolder = Guid.NewGuid();
            Session = SavedSession().Document["session"]!;
            Session.AsObject().Remove("disposableSeedMarker");
            Session.AsObject().Remove("selectedSpaceID");
            var space = Session["spaces"]![0]!.AsObject();
            space["id"] = SwiftId(Space);
            space["tabs"] = new JsonArray(Tab(SavedInFolder, TabPlacement.Saved, SavedFolder), Tab(LooseSaved, TabPlacement.Saved, null),
                Tab(OpenInFolder, TabPlacement.Current, openFolder), Tab(Shown, TabPlacement.Current, null),
                Tab(NextOpen, TabPlacement.Current, null));
            space["folders"] = new JsonArray(Folder(SavedFolder, TabPlacement.Saved), Folder(openFolder, TabPlacement.Current));
            space.Remove("selectedTabID");
        }

        private static JsonObject Tab(Guid id, TabPlacement placement, Guid? folder) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Page",
            ["url"] = $"https://folders.example/{id}",
            ["placement"] = placement.Name,
            ["savedURL"] = placement.IsDurable ? $"https://folders.example/{id}" : null,
            ["folderID"] = folder is { } folderId ? SwiftId(folderId) : null,
            ["symbol"] = "globe",
            ["lastActivatedAt"] = 800000000.0
        };

        private static JsonObject Folder(Guid id, TabPlacement location) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Folder",
            ["location"] = location.Name,
            ["isCollapsed"] = true
        };
    }

    [Fact]
    public void ASpaceFallsBackOnlyToATabItsSidebarShows() {
        var fixture = new CollapsedFoldersSpace();
        using var device = new TestDevice(fixture.Session);
        var window = device.Open(fixture.Space, (fixture.Space, fixture.Shown));

        // Deleting the shown tab, with no tab to go back to, passes the open
        // tab inside a collapsed folder.
        device.Send(new DeleteTab(device.Workspace, window, fixture.Space, fixture.Shown));
        Assert.Equal(fixture.NextOpen, device.Tab(window, fixture.Space));

        // Clearing the open tabs passes the first saved tab, inside a
        // collapsed folder, for the loose one, and so does a new window.
        device.Send(new ClearCurrentTabs(device.Workspace, window, fixture.Space, Guid.NewGuid()));
        Assert.Equal(fixture.LooseSaved, device.Tab(window, fixture.Space));
        Assert.Equal(fixture.LooseSaved, device.Tab(device.Open(fixture.Space), fixture.Space));

        // Opened, the folder's tab is the first saved tab again.
        device.Send(new CollapseFolder(device.Workspace, fixture.Space, fixture.SavedFolder, Collapsed: false));
        Assert.Equal(fixture.SavedInFolder, device.Tab(device.Open(fixture.Space), fixture.Space));

        // With the Saved section collapsed the sidebar shows no tab, so a
        // window shows none.
        device.Send(new ExpandSavedTabs(device.Workspace, fixture.Space, IsExpanded: false));
        Assert.Null(device.Tab(device.Open(fixture.Space), fixture.Space));
    }

    [Fact]
    public void TakingBackAClearReopensItsTabsWhereTheyStoodInTheirFolderAndSplit() {
        var fixture = new BatchSpace();
        using var device = new TestDevice(fixture.Session);
        var window = device.Open(fixture.Space, (fixture.Space, fixture.Open));
        var before = device.Authority.Current.KnownSpace(fixture.Space);
        var clear = Guid.NewGuid();

        // Clearing the other tabs archives the split, the last tab and the
        // open folder's only tab, and the emptied folder goes.
        device.Send(new ClearCurrentTabs(device.Workspace, window, fixture.Space, clear, KeepsShownTab: true));
        var cleared = device.Authority.Current.KnownSpace(fixture.Space);
        Assert.Equal([fixture.Pinned, fixture.Saved, fixture.Open], cleared.Tabs.Select(tab => tab.Id));
        Assert.DoesNotContain(cleared.Folders, folder => folder.Id == fixture.OpenFolder);
        Assert.Empty(cleared.SplitGroups);

        // Taken back after a new tab opened and showed, each tab returns where
        // it stood, after the tab it followed, with its folder and split as
        // they were; the new tab follows them, and the window shows the tab
        // it showed when it cleared.
        var opened = Guid.NewGuid();
        device.Send(new OpenTab(device.Workspace, window, fixture.Space, opened, new TabContent("https://opened.example/", View: null,
            Title: null), TabPlacement.Current, AfterTabId: fixture.Open, Shows: true));
        var reopened = device.Send(new RestoreClearedTabs(device.Workspace, window, fixture.Space, clear));
        var restored = device.Authority.Current.KnownSpace(fixture.Space);
        Assert.Equal([fixture.Pinned, fixture.Saved, fixture.Open, fixture.Left, fixture.Right, fixture.Last, fixture.Filed, opened],
            restored.Tabs.Select(tab => tab.Id));
        Assert.Equal(before.Folders, restored.Folders);
        Assert.Equal(before.SplitGroups, restored.SplitGroups);
        Assert.Equal(before.Tabs.Select(tab => (tab.Id, tab.FolderId, tab.SplitGroupId)),
            restored.Tabs.Where(tab => tab.Id != opened).Select(tab => (tab.Id, tab.FolderId, tab.SplitGroupId)));
        Assert.DoesNotContain(restored.ArchivedTabs, archived => cleared.ArchivedTabs.Any(entry => entry.Tab.Id == archived.Tab.Id
            && entry.ArchivedAt == archived.ArchivedAt && entry.Reason == ArchiveReason.Closed));
        Assert.Equal(fixture.Open, device.Tab(window, fixture.Space));
        Assert.Equal([fixture.Left, fixture.Right, fixture.Last, fixture.Filed],
            reopened.OfType<TabsOpened>().Single().Tabs.Select(tab => tab.TabId));

        // Nothing is left to take back a second time.
        Assert.Equal(clear, Assert.IsType<ClearedTabsGone>(Assert.Throws<Rejected>(() =>
            device.Send(new RestoreClearedTabs(device.Workspace, window, fixture.Space, clear))).Rejection).ClearId);

        // Clearing every open tab takes the shown one too, which shows again
        // once the clear is taken back.
        var all = Guid.NewGuid();
        device.Send(new ClearCurrentTabs(device.Workspace, window, fixture.Space, all));
        Assert.Equal(fixture.Pinned, device.Tab(window, fixture.Space));
        device.Send(new RestoreClearedTabs(device.Workspace, window, fixture.Space, all));
        Assert.Equal(restored.Tabs.Select(tab => tab.Id), device.Authority.Current.KnownSpace(fixture.Space).Tabs.Select(tab => tab.Id));
        Assert.Equal(fixture.Open, device.Tab(window, fixture.Space));
    }

    [Fact]
    public void WithNothingCollapsedASpaceFallsBackAsTheSectionRankingAlonePicks() {
        using var device = new TestDevice(MaximalDocument());
        foreach (var space in device.Authority.Current.Spaces) {
            var open = space with {
                Folders = [.. space.Folders.Select(folder => folder with { IsCollapsed = false })],
                Settings = space.Settings with { IsSavedTabsExpanded = true }
            };
            Guid? ranked = TabPlacement.Fallback([.. open.Tabs.Select(tab => tab.Placement)]) is { } index ? open.Tabs[index].Id : null;
            Assert.Equal(ranked, open.FallbackTab());
        }
    }

    [Fact]
    public void OnlyTheWindowThatOpensATabHearsItOpenedAndNeverForAMoveOrAnImport() {
        var fixture = new BatchSpace();
        using var device = new TestDevice(fixture.Session);
        var window = device.Open(fixture.Space, (fixture.Space, fixture.Open));
        var other = device.Open(fixture.Space);
        var opened = Guid.NewGuid();

        var changes = device.Send(new OpenTab(device.Workspace, window, fixture.Space, opened,
            new TabContent("https://opened.example/", View: null, Title: null), TabPlacement.Current, AfterTabId: null, Shows: false));
        Assert.Equal([new OpenedTab(fixture.Space, opened)], changes.OfType<TabsOpened>().Single(change => change.WindowId == window).Tabs);
        Assert.DoesNotContain(changes.OfType<TabsOpened>(), change => change.WindowId == other);

        // A copy and a closed tab brought back are opened too.
        var copied = device.Send(new DuplicateTab(device.Workspace, window, fixture.Space, opened, Placement: null, Shows: false));
        Assert.Equal(copied.OfType<TabCopied>().Single().CopyTabId, copied.OfType<TabsOpened>().Single().Tabs.Single().TabId);
        device.Send(new CloseTab(device.Workspace, window, fixture.Space, opened));
        Assert.Equal([new OpenedTab(fixture.Space, opened)],
            device.Send(new ReopenClosedTab(device.Workspace, window, fixture.Space)).OfType<TabsOpened>().Single().Tabs);

        // A tab that only moves to another Space did not open.
        Assert.Empty(device.Send(new MoveTabToSpace(device.Workspace, window, fixture.Space, opened, fixture.Other, null, null, null))
            .OfType<TabsOpened>());

        // An imported Space's tabs are the import's, not the window's.
        Assert.Empty(device.Send(new ImportSpaces(device.Workspace, window, ReadSpaces(fixture.Session["spaces"]![0]!)))
            .OfType<TabsOpened>());
    }

}
