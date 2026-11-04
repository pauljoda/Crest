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

    /// The core judges a page's security from the facts its engine reports,
    /// the same way for every engine: plain HTTP is insecure except on this
    /// device's own host, a secure connection is secure until what it carried,
    /// a warning or its certificate says otherwise, and a malicious page
    /// outranks everything.
    [Theory]
    [InlineData("http://example.org/", false, false, false, false, PageMixedContent.None, false, false, "insecure")]
    [InlineData("http://localhost:8080/", false, false, false, false, PageMixedContent.None, false, false, "none")]
    [InlineData("http://app.localhost/", false, false, false, false, PageMixedContent.None, false, false, "none")]
    [InlineData("http://127.0.0.1:5000/", false, false, false, false, PageMixedContent.None, false, false, "none")]
    [InlineData("http://[::1]:5000/", false, false, false, false, PageMixedContent.None, false, false, "none")]
    [InlineData("data:text/html,hi", false, false, false, true, PageMixedContent.None, false, false, "insecure")]
    [InlineData("file:///tmp/page.html", false, false, false, false, PageMixedContent.None, false, false, "none")]
    [InlineData("https://example.org/", true, false, false, false, PageMixedContent.None, false, false, "none")]
    [InlineData("https://example.org/", true, true, false, false, PageMixedContent.None, false, false, "secure")]
    [InlineData("https://example.org/", true, true, false, true, PageMixedContent.None, false, false, "insecure")]
    [InlineData("https://example.org/", true, true, false, true, PageMixedContent.Displayed, false, false, "mixed_content")]
    [InlineData("https://example.org/", true, true, true, false, PageMixedContent.Ran, false, false, "certificate_error")]
    [InlineData("https://example.org/", true, true, false, false, PageMixedContent.None, false, true, "none")]
    [InlineData("https://example.org/", true, true, true, false, PageMixedContent.None, true, false, "dangerous")]
    public void APageSecurityIsJudgedFromWhatItsEngineKnows(string url, bool cryptographic, bool judged, bool certificateError,
        bool warns, PageMixedContent mixed, bool malicious, bool errorPage, string expected) {
        var facts = new PageSecurityFacts(cryptographic, judged, certificateError, warns, mixed, malicious, errorPage);

        Assert.Equal(PageSecurity.Named(expected), PageSecurity.Judging(facts, url));
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
