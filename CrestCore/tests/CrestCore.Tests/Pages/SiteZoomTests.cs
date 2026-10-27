using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void SiteZoomSurvivesPageClosureAndRelaunchAndResetRemovesOnlyThatHost() {
        using var directory = new StorageDirectory();
        Guid spaceId;
        {
            var (app, workspace, _) = DeviceApp(directory);
            using var disposal = app;
            var engine = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, true), _ => { });
            spaceId = app.Workspace(workspace).Current.Spaces.First().Id;
            var window = Guid.NewGuid();
            app.Send(new OpenWindow(window, workspace, false, null, spaceId, [], true));
            var (_, page) = LiveTab(app, engine, workspace, window, spaceId);
            var change = Assert.Single(app.Send(new SetSiteZoom(page, "https://EXAMPLE.com./one", 1.5)).OfType<SiteZoomChanged>());
            Assert.Equal(app.Workspace(workspace).Current.Spaces.Single(space => space.Id == spaceId).ProfileId, change.ProfileId);
            Assert.Equal("example.com", change.Host);
            Assert.Equal(new SiteZoomPreference("example.com", 1.5), app.Query(new GetSiteZoom(page, "http://example.com:8080/two")));
            Assert.Null(app.Query(new GetSiteZoom(page, "https://sub.example.com/")).Factor);
            Assert.Null(app.Query(new GetSiteZoom(page, "https://other.example/")).Factor);
            app.Send(new SetSiteZoom(page, "https://other.example/", 0.9));
            app.Send(new SetSiteZoom(page, "http://[::1]:8080/", 0.85));
            app.Send(new ReleasePage(page, false));
            var (_, reopened) = LiveTab(app, engine, workspace, window, spaceId);
            Assert.Equal(1.5, app.Query(new GetSiteZoom(reopened, "https://example.com/")).Factor);
        }
        {
            var (app, workspace, _) = DeviceApp(directory);
            using var disposal = app;
            var engine = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, true), _ => { });
            var window = Guid.NewGuid();
            app.Send(new OpenWindow(window, workspace, false, null, spaceId, [], true));
            var (_, page) = LiveTab(app, engine, workspace, window, spaceId);
            Assert.Equal(1.5, app.Query(new GetSiteZoom(page, "https://example.com/")).Factor);
            Assert.Equal(0.85, app.Query(new GetSiteZoom(page, "https://[::1]/")).Factor);
            app.Send(new SetSiteZoom(page, "https://example.com/", null));
            Assert.Null(app.Query(new GetSiteZoom(page, "https://example.com/")).Factor);
            Assert.Equal(0.9, app.Query(new GetSiteZoom(page, "https://other.example/")).Factor);
        }
        var (again, kept, _) = DeviceApp(directory);
        using var finalDisposal = again;
        var finalEngine = again.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, true), _ => { });
        var finalWindow = Guid.NewGuid();
        again.Send(new OpenWindow(finalWindow, kept, false, null, spaceId, [], true));
        var (_, restored) = LiveTab(again, finalEngine, kept, finalWindow, spaceId);
        Assert.Null(again.Query(new GetSiteZoom(restored, "https://example.com/")).Factor);
        Assert.Equal(0.9, again.Query(new GetSiteZoom(restored, "https://other.example/")).Factor);
    }

    [Fact]
    public void SiteZoomIsIsolatedByProfileAndPrivatePreferencesNeverReachDisk() {
        using var directory = new StorageDirectory();
        Guid privateProfile;
        {
            var (app, workspace, _) = DeviceApp(directory);
            using var disposal = app;
            var engine = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, true), _ => { });
            var spaces = app.Workspace(workspace).Current.Spaces;
            var window = Guid.NewGuid();
            app.Send(new OpenWindow(window, workspace, false, null, spaces[0].Id, [], true));
            var (_, page) = LiveTab(app, engine, workspace, window, spaces[0].Id);
            var (_, other) = LiveTab(app, engine, workspace, window, spaces[1].Id);
            app.Send(new SetSiteZoom(page, "https://example.com/", 1.25));
            Assert.Null(app.Query(new GetSiteZoom(other, "https://example.com/")).Factor);
            app.Send(new SetSiteZoom(other, "https://example.com/", 0.9));

            var borrowing = TestWorkspaces.Opened(app.Send(new BorrowSpace(workspace, spaces[0].Id, spaces[0].ProfileId)));
            var borrowedWindow = Guid.NewGuid();
            app.Send(new OpenWindow(borrowedWindow, borrowing, false, null, spaces[0].Id, [], true));
            var (_, borrowedPage) = LiveTab(app, engine, borrowing, borrowedWindow, spaces[0].Id);
            Assert.Equal(1.25, app.Query(new GetSiteZoom(borrowedPage, "https://example.com/")).Factor);
            app.Send(new SetSiteZoom(borrowedPage, "https://example.com/", 1.5));
            Assert.Equal(1.5, app.Query(new GetSiteZoom(page, "https://example.com/")).Factor);
            app.Send(new SetSiteZoom(page, "https://example.com/", 1.25));

            var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, null)));
            var privateSpace = app.Workspace(privateWorkspace).Current.Spaces.Single();
            privateProfile = privateSpace.ProfileId;
            var privateWindow = Guid.NewGuid();
            app.Send(new OpenWindow(privateWindow, privateWorkspace, false, null, privateSpace.Id, [], true));
            var (_, privatePage) = LiveTab(app, engine, privateWorkspace, privateWindow, privateSpace.Id);
            Assert.Null(app.Query(new GetSiteZoom(privatePage, "https://example.com/")).Factor);
            app.Send(new SetSiteZoom(privatePage, "https://example.com/", 2));
            Assert.Equal(2, app.Query(new GetSiteZoom(privatePage, "https://example.com/")).Factor);
            Assert.Equal(1.25, app.Query(new GetSiteZoom(page, "https://example.com/")).Factor);
            app.Send(new CloseWorkspace(privateWorkspace));
            app.Send(new BeginDeletingSpace(workspace, window, spaces[1].Id, Guid.NewGuid()));
        }
        using var connection = SqliteConnection.Open(directory.File, Sqlite.OpenReadOnly);
        var choices = connection.ReadDevice().SiteZoom;
        Assert.DoesNotContain(choices, choice => choice.ProfileId == privateProfile);
        Assert.Equal(1.25, Assert.Single(choices).Factor);
    }

    [Fact]
    public void SiteZoomRejectsInvalidValuesAndLockedSpacesAndNormalizesInternationalHosts() {
        var session = TwoSpaceSession();
        session["spaces"]![0]!["accessPolicy"] = "deviceOwnerAuthentication";
        var (app, engine, _, workspace, window) = PageHost(session);
        using var disposal = app;
        var space = app.Workspace(workspace).Current.Spaces.First().Id;
        Unlock(app.Send, workspace, space);
        var (_, page) = LiveTab(app, engine, workspace, window, space);
        foreach (var factor in new[] { double.NaN, double.PositiveInfinity, 0.24, 5.01 })
            Assert.IsType<InvalidSiteZoom>(Refusal(app, new SetSiteZoom(page, "https://example.com/", factor)));
        Assert.IsType<InvalidSiteZoomAddress>(Refusal(app, new SetSiteZoom(page, "file:///tmp/example.html", 1.5)));
        Assert.Equal(new SiteZoomPreference(null, null), app.Query(new GetSiteZoom(page, "about:blank")));
        app.Send(new SetSiteZoom(page, "https://b\u00fccher.example/", 1.75));
        Assert.Equal(new SiteZoomPreference("xn--bcher-kva.example", 1.75), app.Query(new GetSiteZoom(page, "http://xn--bcher-kva.example/")));
        app.Send(new LockSpace(space));
        Assert.Equal(new SpaceLocked(space), Refusal(app, new SetSiteZoom(page, "https://example.com/", 1.5)));
        Assert.Equal(new SpaceLocked(space), Assert.Throws<Rejected>(() => app.Query(new GetSiteZoom(page, "https://example.com/"))).Rejection);
    }
}
