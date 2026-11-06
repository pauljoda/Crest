using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Opening, closing, deleting, clearing, copying and moving tabs: where a tab
/// lands, what its section refuses, what closing keeps, and which tab a window
/// shows afterwards.
public sealed partial class BrowserContractsTests {
    /// A saved session whose saved tab is an open split member with a partner,
    /// followed by an open tab of its own.
    private static (JsonNode Session, Guid Space, Guid Member, Guid Partner, Guid Plain) SplitSession() {
        var f = SavedSession(); var space = f.Document["session"]!["spaces"]![0]!;
        var group = SwiftId(Guid.NewGuid()); var partner = Guid.NewGuid(); var plain = Guid.NewGuid();
        var first = space["tabs"]![0]!.AsObject();
        first["placement"] = "current"; first["folderID"] = null; first["savedURL"] = null; first["splitGroupID"] = group.DeepClone();
        JsonObject Current(Guid id, JsonNode? split) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Page",
            ["url"] = "https://example.org/" + id,
            ["placement"] = "current",
            ["symbol"] = "globe",
            ["lastActivatedAt"] = 800000000.0,
            ["splitGroupID"] = split
        };
        space["tabs"]!.AsArray().Add(Current(partner, group.DeepClone()));
        space["tabs"]!.AsArray().Add(Current(plain, null));
        return (f.Document["session"]!, f.Space, f.Tab, partner, plain);
    }

    private static TabContent Page(string address, string? title = null) => new(address, View: null, title);

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

    /// A Space with no pinned tab whose first saved tab and first open tab
    /// each sit in a collapsed folder, ahead of a loose saved tab and two loose
    /// open tabs.
    private sealed class FoldedSpace {
        public Guid Space { get; } = Guid.NewGuid();
        public Guid FoldedSaved { get; } = Guid.NewGuid();
        public Guid LooseSaved { get; } = Guid.NewGuid();
        public Guid FoldedOpen { get; } = Guid.NewGuid();
        public Guid Shown { get; } = Guid.NewGuid();
        public Guid NextOpen { get; } = Guid.NewGuid();
        public JsonNode Session { get; }

        public FoldedSpace() {
            Guid savedFolder = Guid.NewGuid(), openFolder = Guid.NewGuid();
            Session = SavedSession().Document["session"]!;
            Session.AsObject().Remove("disposableSeedMarker");
            Session.AsObject().Remove("selectedSpaceID");
            var space = Session["spaces"]![0]!.AsObject();
            space["id"] = SwiftId(Space);
            space["tabs"] = new JsonArray(Tab(FoldedSaved, "saved", savedFolder), Tab(LooseSaved, "saved", null),
                Tab(FoldedOpen, "current", openFolder), Tab(Shown, "current", null), Tab(NextOpen, "current", null));
            space["folders"] = new JsonArray(Folder(savedFolder, "saved"), Folder(openFolder, "current"));
            space.Remove("selectedTabID");
        }

        private static JsonObject Tab(Guid id, string placement, Guid? folder) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Page",
            ["url"] = $"https://folded.example/{id}",
            ["placement"] = placement,
            ["savedURL"] = placement == "current" ? null : $"https://folded.example/{id}",
            ["folderID"] = folder is { } folderId ? SwiftId(folderId) : null,
            ["symbol"] = "globe",
            ["lastActivatedAt"] = 800000000.0
        };

        private static JsonObject Folder(Guid id, string location) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Folder",
            ["location"] = location,
            ["isCollapsed"] = true
        };
    }

    [Fact]
    public void ATabTheSpaceFallsBackToIsOneThePersonCanSeeInTheSidebar() {
        var f = new FoldedSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.Shown));

        // Deleting the shown tab skips the open tab in a collapsed folder.
        device.Send(new DeleteTab(device.Workspace, window, f.Space, f.Shown));
        Assert.Equal(f.NextOpen, device.Tab(window, f.Space));

        // Clearing the open tabs skips the saved tab in a collapsed folder.
        device.Send(new ClearCurrentTabs(device.Workspace, window, f.Space));
        Assert.Equal(f.LooseSaved, device.Tab(window, f.Space));

        // With the Saved section collapsed too, a window that shows the Space
        // on its own shows no tab.
        device.Send(new ExpandSavedTabs(device.Workspace, f.Space, IsExpanded: false));
        Assert.Null(device.Tab(device.Open(f.Space), f.Space));
    }
}
