using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// A Quick Window's or Peek's page becomes a tab or an archived tab once, and
/// a tab takes the live page only where the page already lives.
public sealed partial class BrowserContractsTests {
    /// Opens a Quick Window's page in `space`, hosted by `window`.
    private static Guid TransientPage(TestDevice device, Guid space, Guid window) {
        var page = Guid.NewGuid();
        device.Send(new OpenPage(page, device.Workspace, space, null, window));
        return page;
    }

    [Fact]
    public void APromotedPageBecomesATabOnceAndTheTabTakesThePageOnlyInItsOwnSpace() {
        var session = TwoSpaceSession();
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        device.Register(EngineCapability.WorkspaceTransfer);
        Guid first = SpaceId(session["spaces"]![0]!), second = SpaceId(session["spaces"]![1]!);
        var window = device.Open(first, (first, TabId(session["spaces"]![0]!, 0)));
        var page = TransientPage(device, first, window);
        var promoting = new PromoteTransientPage(device.Workspace, window, page, first, TabPlacement.Current, "https://quick.example/read");

        var promoted = Assert.Single(device.Send(promoting).OfType<TransientPagePromoted>());
        Assert.True(promoted.AdoptsPage);
        var tab = core.Current.Spaces[0].Tabs.Single(candidate => candidate.Id == promoted.TabId);
        Assert.Equal(("quick.example", "https://quick.example/read", TabPlacement.Current), (tab.Title, tab.Url, tab.Placement));
        Assert.Equal(promoted.TabId, device.Tab(window, first));

        Assert.Equal(page, Assert.IsType<TransientAlreadyCompleted>(Assert.Throws<Rejected>(() => device.Send(promoting)).Rejection).PageId);
        Assert.IsType<TransientAlreadyCompleted>(Assert.Throws<Rejected>(() =>
            device.Send(new ArchiveTransientPage(device.Workspace, page, first, "https://quick.example/read", null))).Rejection);

        // Another Space's tab opens a page of its own, and the window follows it there.
        var other = TransientPage(device, first, window);
        Assert.False(Assert.Single(device.Send(new PromoteTransientPage(device.Workspace, window, other, second, TabPlacement.Current,
            "https://peek.example/")).OfType<TransientPagePromoted>()).AdoptsPage);
        Assert.Equal(2, core.Current.Spaces[1].Tabs.Count);
        Assert.Equal(second, device.Space(window));
        var unknown = Guid.NewGuid();
        Assert.Equal(unknown, Assert.IsType<UnknownPage>(Assert.Throws<Rejected>(() => device.Send(
            promoting with { PageId = unknown })).Rejection).PageId);
    }

    [Fact]
    public void AnEngineThatCannotMoveAPageBetweenWindowsLeavesThePromotedTabToOpenItsOwn() {
        var session = SavedSession().Document["session"]!;
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        device.Register();
        var space = SpaceId(session["spaces"]![0]!);
        var window = device.Open(space);
        var page = TransientPage(device, space, window);

        Assert.False(Assert.Single(device.Send(new PromoteTransientPage(device.Workspace, window, page, space, TabPlacement.Current,
            "https://quick.example/")).OfType<TransientPagePromoted>()).AdoptsPage);
    }

    [Fact]
    public void AnArchivedPageIsKeptOnceInItsSpacesArchiveEvenAfterItsPageIsGone() {
        var session = TwoSpaceSession();
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        device.Register();
        Guid first = SpaceId(session["spaces"]![0]!), second = SpaceId(session["spaces"]![1]!);
        var window = device.Open(first, (first, TabId(session["spaces"]![0]!, 0)));
        var shown = device.Shown(window);
        var page = TransientPage(device, first, window);
        ArchiveTransientPage Archiving(Guid pageId, Guid space, string address, string? title) =>
            new(device.Workspace, pageId, space, address, title);

        var mismatch = Assert.IsType<PageProfileMismatch>(Assert.Throws<Rejected>(() =>
            device.Send(Archiving(page, second, "https://idle.example/", "Idle"))).Rejection);
        Assert.Equal((page, second), (mismatch.PageId, mismatch.SpaceId));
        device.Send(Archiving(page, first, "https://idle.example/", "Idle"));
        var archived = core.Current.Spaces[0].ArchivedTabs[^1];
        Assert.Equal((ArchiveReason.QuickWindow, "Idle", TabPlacement.Current), (archived.Reason, archived.Tab.Title, archived.Tab.Placement));
        Assert.Equal(shown, device.Shown(window));
        Assert.IsType<TransientAlreadyCompleted>(Assert.Throws<Rejected>(() =>
            device.Send(Archiving(page, first, "https://idle.example/", "Idle"))).Rejection);

        // A page memory pressure took back is archived where it lived, titled by its host.
        var released = TransientPage(device, first, window);
        device.Send(new ReleasePage(released, KeepsState: false));
        device.Send(Archiving(released, first, "https://released.example/", ""));
        Assert.Equal("released.example", core.Current.Spaces[0].ArchivedTabs[^1].Tab.Title);
    }
}
