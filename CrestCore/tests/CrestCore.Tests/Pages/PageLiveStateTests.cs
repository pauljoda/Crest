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

    /// A site typed without a scheme that https can't reach loads over http,
    /// once. An address typed with https://, one Crest holds, and a failure
    /// http can't fix all stay failures.
    [Fact]
    public void OnlyASiteTypedWithoutASchemeFallsBackToHttp() {
        var (app, engine, binding, page, _, window, _, _) = LivePage();
        PageFailure Unreachable(string url) => new(NavigationError.SecureConnectionFailed, url, ReplacedDocument: true, "net", -113);

        // The palette opens the address its row resolved, then records the pick.
        app.Send(new LoadAddress(page, "https://httpforever.org"));
        app.Send(new RecordPaletteChoice(window, "httpforever.org", PaletteRow.Of(PaletteRowKind.OpenAddress, "Open httpforever.org",
            "https://httpforever.org", address: "https://httpforever.org", httpFallback: "http://httpforever.org")));
        app.Drain();
        app.Report(engine, new NavigationFailed(page, Unreachable("https://httpforever.org/")));
        Assert.Equal(new LoadPage(page, "http://httpforever.org"), binding.Commands[^1]);
        app.Drain();

        // A history row, or the address row of a site the Space knows, opens
        // an address Crest holds, even after the site was typed without a scheme.
        foreach (var held in new[] {
            PaletteRow.Of(PaletteRowKind.History, "Example", "https://example.org", address: "https://example.org"),
            PaletteRow.Of(PaletteRowKind.OpenAddress, "Open example.org", "https://example.org", address: "https://example.org") }) {
            app.Send(new LoadAddress(page, "https://example.org"));
            app.Send(new RecordPaletteChoice(window, "example.org", held));
            var opened = binding.Commands.Count;
            app.Drain();
            app.Report(engine, new NavigationFailed(page, Unreachable("https://example.org/")));
            Assert.Equal(opened, binding.Commands.Count);
            Assert.NotNull(Live(app.Drain()).Failure);
        }

        app.Send(new Navigate(page, "httpforever.com"));
        Assert.Equal(new LoadPage(page, "https://httpforever.com"), binding.Commands[^1]);
        app.Report(engine, new NavigationFailed(page, Unreachable("https://httpforever.com/")));
        Assert.Equal(new LoadPage(page, "http://httpforever.com"), binding.Commands[^1]);
        app.Drain();

        // Each fallback is taken once.
        app.Report(engine, new NavigationFailed(page, Unreachable("https://httpforever.com/")));
        Assert.NotNull(Live(app.Drain()).Failure);

        foreach (var load in new PageIntent[] { new Navigate(page, "https://example.org"), new LoadAddress(page, "https://example.net") }) {
            app.Send(load);
            var loaded = binding.Commands.Count;
            app.Drain();
            app.Report(engine, new NavigationFailed(page, Unreachable(((LoadPage)binding.Commands[^1]).Url)));
            Assert.Equal(loaded, binding.Commands.Count);
            Assert.NotNull(Live(app.Drain()).Failure);
        }

        app.Send(new Navigate(page, "nowhere.example"));
        app.Drain();
        app.Report(engine, new NavigationFailed(page,
            new PageFailure(NavigationError.CannotFindServer, "https://nowhere.example/", ReplacedDocument: true, "net", -105)));
        Assert.Equal(new LoadPage(page, "https://nowhere.example"), binding.Commands[^1]);
    }

    /// A fallback belongs to the load that typed its site: a later load in
    /// the same page, such as the same site typed with https://, or a new
    /// document, ends it, and another page's typed load keeps its own.
    [Fact]
    public void AnHttpFallbackBelongsToItsOwnPagesTypedLoad() {
        var (app, engine, binding, page, workspace, window, space, _) = LivePage();
        PageFailure Unreachable(string url) => new(NavigationError.SecureConnectionFailed, url, ReplacedDocument: true, "net", -113);

        app.Send(new Navigate(page, "example.org"));
        app.Send(new Navigate(page, "https://example.org"));
        var loaded = binding.Commands.Count;
        app.Drain();
        app.Report(engine, new NavigationFailed(page, Unreachable("https://example.org/")));
        Assert.Equal(loaded, binding.Commands.Count);
        Assert.NotNull(Live(app.Drain()).Failure);

        app.Send(new Navigate(page, "example.org"));
        app.Report(engine, new NavigationCommitted(page, "https://example.org/", SameDocument: false));
        loaded = binding.Commands.Count;
        app.Drain();
        app.Report(engine, new NavigationFailed(page, Unreachable("https://example.org/")));
        Assert.Equal(loaded, binding.Commands.Count);
        app.Drain();

        var other = Guid.NewGuid();
        app.Send(new OpenPage(other, workspace, space, null, window));
        app.Report(engine, new PageCreated(other));
        app.Send(new Navigate(page, "example.org"));
        app.Send(new Navigate(other, "example.org"));
        app.Drain();
        app.Report(engine, new NavigationFailed(page, Unreachable("https://example.org/")));
        Assert.Equal(new LoadPage(page, "http://example.org"), binding.Commands[^1]);
        app.Report(engine, new NavigationFailed(other, Unreachable("https://example.org/")));
        Assert.Equal(new LoadPage(other, "http://example.org"), binding.Commands[^1]);
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
