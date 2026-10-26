using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// A page's live state: what its engine shows reaches readers once per real
/// change and once per drain, a failure stays until the page moves on, and a
/// load the person asks for resolves by the core's address rules.
public sealed partial class BrowserContractsTests {
    /// A live page for the fixture tab of a saved session's first Space, on
    /// the default engine of `PageHost`.
    private static (CrestApp App, Engine Engine, RecordingEngine Binding, Guid Page, Guid Workspace, Guid Window, Guid Space, Guid Tab)
        LivePage() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        var (app, engine, binding, workspace, window) = PageHost(session);
        var page = Guid.NewGuid();
        app.Send(new OpenPage(page, workspace, fixture.Space, fixture.Tab, window));
        app.Report(engine, new PageCreated(page));
        app.Drain();
        return (app, engine, binding, page, workspace, window, fixture.Space, fixture.Tab);
    }

    private static PageSnapshot Showing(string url, string title = "", bool isLoading = false) =>
        PageSnapshot.Blank with { Url = url, Title = title, IsLoading = isLoading };

    private static PageLiveState Live(IReadOnlyList<Change> changes) => Assert.IsType<PageChanged>(Assert.Single(changes)).Page.Live;

    [Fact]
    public void ASavedTabReturnsHomeWhenItOrItsPageHasLeftIt() {
        var (app, engine, _, page, workspace, window, space, tab) = LivePage();
        using var disposal = app;
        bool Returns() => app.Query(new CanReturnToSavedAddress(workspace, window, space, tab)).ChangesPage;

        // The fixture's saved tab shows another page than the one it was saved at.
        Assert.True(Returns());
        app.Send(new ReturnToSavedAddress(workspace, space, tab));
        Assert.False(Returns());

        // Its page heading within the saved page is still home; heading elsewhere is not.
        app.Report(engine, new PageStateChanged(page, PageSnapshot.Blank with { PendingUrl = "https://example.com/#top" }));
        app.Drain();
        Assert.False(Returns());
        app.Report(engine, new PageStateChanged(page, PageSnapshot.Blank with { PendingUrl = "https://elsewhere.example/" }));
        app.Drain();
        Assert.True(Returns());

        // Commit clears the pending URL before the document finishes. The
        // live address still differs even though the saved tab has not updated.
        app.Report(engine, new PageStateChanged(page, PageSnapshot.Blank with { Url = "https://elsewhere.example/", IsLoading = true }));
        app.Report(engine, new NavigationCommitted(page, "https://elsewhere.example/", SameDocument: false));
        app.Drain();
        Assert.True(Returns());

        // Returning home takes effect immediately, even if the stored tab
        // still describes a completed navigation away from home.
        app.Report(engine, new NavigationFinished(page, "https://elsewhere.example/", "Elsewhere"));
        app.Drain();
        app.Report(engine, new PageStateChanged(page, PageSnapshot.Blank with { Url = "https://elsewhere.example/", PendingUrl = "https://example.com/", IsLoading = true }));
        app.Drain();
        Assert.False(Returns());
        Assert.False(app.Query(new CanReturnToSavedAddress(workspace, window, space, Guid.NewGuid())).ChangesPage);
    }

    [Fact]
    public void NavigateLoadsInternalPagesOnlyOnAnEngineThatShowsThemAndNeverInALockedSpace() {
        var session = SavedSession().Document["session"]!;
        var space = SpaceId(session["spaces"]![0]!);
        using var app = new CrestApp();
        var binding = new RecordingEngine();
        var engine = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium,
            [.. EngineCapability.Required, EngineCapability.InternalPages], IsDefault: true), binding.Run);
        var workspace = TestWorkspaces.Open(app, session);
        var authority = app.Workspace(workspace);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        var page = Guid.NewGuid();
        app.Send(new OpenPage(page, workspace, space, null, window));
        app.Report(engine, new PageCreated(page));

        app.Send(new Navigate(page, "chrome://flags"));
        Assert.Equal(new LoadPage(page, "chrome://flags"), binding.Commands[^1]);

        // The Space asks for authentication from now on, and this process
        // holds no grant for it.
        app.Send(new SetSpaceAccess(workspace, space, SpaceAccessPolicy.DeviceOwnerAuthentication));
        Assert.Equal(new SpaceLocked(space), Refusal(app, new Navigate(page, "example.org")));
    }
}
