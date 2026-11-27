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
        device.Send(new ClearCurrentTabs(device.Workspace, window, fixture.Space));
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
