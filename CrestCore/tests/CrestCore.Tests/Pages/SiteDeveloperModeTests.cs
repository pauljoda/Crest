using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Whether a site's pages show Developer Mode: a choice reaches every open
/// page of the site at once, the device store keeps the choices made in the
/// persistent session, and a private Space's choices stay in memory and in
/// that Space.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ASiteDeveloperModeChoiceReachesEveryPageOfTheSiteAndSurvivesRelaunchButAPrivateOneDoesNot() {
        using var directory = new StorageDirectory();
        const string site = "https://dev.example/";
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            var (engine, window) = DeveloperModeHost(app, workspace);
            var space = SpaceId(spaces[0]!);
            var first = ShowingPage(app, engine, workspace, space, TabId(spaces[0]!, 0), window, site);
            var second = ShowingPage(app, engine, workspace, space, TabId(spaces[0]!, 1), window, "https://dev.example/docs");
            var elsewhere = ShowingPage(app, engine, workspace, space, TabId(spaces[0]!, 2), window, "https://other.example/");
            Assert.Null(app.Pages.Known(first).State.DeveloperMode);

            var chosen = app.Send(new ChooseSiteDeveloperMode(first, IsOn: true)).OfType<PageChanged>().Select(change => change.Page).ToArray();
            Assert.Equal(new[] { first, second }.Order(), chosen.Select(page => page.Id).Order());
            Assert.All(chosen, page => Assert.True(page.DeveloperMode));
            Assert.Empty(app.Send(new ChooseSiteDeveloperMode(second, IsOn: true)).OfType<PageChanged>());

            // A page that moves to the site takes its choice.
            app.Report(engine, new PageStateChanged(elsewhere, Showing("https://dev.example/login")));
            Assert.True(Assert.Single(app.Drain().OfType<PageChanged>()).Page.DeveloperMode);

            // A private Space's choice holds there alone.
            var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, null)));
            var privateWindow = Guid.NewGuid();
            app.Send(new OpenWindow(privateWindow, privateWorkspace, Saved: false, null, null, [], RestoresTabs: true));
            var privateSpace = app.Workspace(privateWorkspace).Current.Spaces[0].Id;
            var privatePage = ShowingPage(app, engine, privateWorkspace, privateSpace, null, privateWindow, site);
            Assert.True(app.Pages.Known(privatePage).State.DeveloperMode);
            app.Send(new ChooseSiteDeveloperMode(privatePage, IsOn: false));
            Assert.False(app.Pages.Known(privatePage).State.DeveloperMode);
            Assert.True(app.Pages.Known(first).State.DeveloperMode);
        }
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            var (engine, window) = DeveloperModeHost(app, workspace);
            var page = ShowingPage(app, engine, workspace, SpaceId(spaces[0]!), TabId(spaces[0]!, 0), window, site);
            Assert.True(app.Pages.Known(page).State.DeveloperMode);

            // Forgetting the choice returns the site to the default.
            Assert.Null(Assert.Single(app.Send(new ChooseSiteDeveloperMode(page, IsOn: null)).OfType<PageChanged>()).Page.DeveloperMode);
            Assert.IsType<PageShowsNoSite>(Refusal(app, new ChooseSiteDeveloperMode(
                ShowingPage(app, engine, workspace, SpaceId(spaces[0]!), TabId(spaces[0]!, 1), window, "about:blank"), IsOn: true)));
        }
    }

    /// Registers a default WebKit binding on `app` and opens a window over `workspace`.
    private static (Engine Engine, Guid Window) DeveloperModeHost(CrestApp app, Guid workspace) {
        var engine = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true), _ => { });
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        app.Drain();
        return (engine, window);
    }

    /// Opens a live page for `tab`, or a Quick Window's page without one, that shows `url`.
    private static Guid ShowingPage(CrestApp app, Engine engine, Guid workspace, Guid space, Guid? tab, Guid window, string url) {
        var page = Guid.NewGuid();
        app.Send(new OpenPage(page, workspace, space, tab, window, tab is null ? TransientPresentation.QuickWindow : null));
        app.Report(engine, new PageCreated(page));
        app.Report(engine, new PageStateChanged(page, Showing(url)));
        app.Drain();
        return page;
    }
}
