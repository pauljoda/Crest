using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// The core's pages: who owns each page, which engine hosts it, where it stands
/// there, the rules that refuse a page, and the order commands reach engines.
public sealed partial class BrowserContractsTests {
    /// An engine binding under test. It records every command it runs, fails
    /// when one runs on the stack of another, and runs `OnCommand` on each.
    private sealed class RecordingEngine {
        private bool running;

        public List<EngineCommand> Commands { get; } = [];

        public Action<EngineCommand>? OnCommand { get; set; }

        public void Run(EngineCommand command) {
            Assert.False(running, $"{command} ran on the stack of another command.");
            running = true;
            try {
                Commands.Add(command);
                OnCommand?.Invoke(command);
            } finally {
                running = false;
            }
        }
    }

    /// A memory-only app hosting the pages of a workspace of `kind`, opened
    /// from `session`, on a default WebKit binding, with one window open over it.
    private static (CrestApp App, Engine Engine, RecordingEngine Binding, Guid Workspace, Guid Window) PageHost(
        JsonNode session, WorkspaceKind? kind = null) {
        var app = new CrestApp();
        var binding = new RecordingEngine();
        var engine = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true), binding.Run);
        var workspace = TestWorkspaces.Open(app, session, kind);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        return (app, engine, binding, workspace, window);
    }

    /// A saved session with a second Space of its own profile.
    private static JsonNode TwoSpaceSession() {
        var session = SavedSession().Document["session"]!;
        session["spaces"]!.AsArray().Add(SavedSession().Document["session"]!["spaces"]![0]!.DeepClone());
        return session;
    }

    private static Guid ProfileId(JsonNode space) => Guid.Parse(space["profile"]!["id"]!.GetValue<string>());

    private static Rejection Refusal(CrestApp app, Intent intent) => Assert.Throws<Rejected>(() => app.Send(intent)).Rejection;

    [Fact]
    public void APageOpensOnTheDefaultEngineGoesLiveWhenCreatedAndIsGoneOnceReleased() {
        var session = TwoSpaceSession();
        var (space, tab) = (SpaceId(session["spaces"]![0]!), TabId(session["spaces"]![0]!, 0));
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var page = Guid.NewGuid();

        var opened = Assert.IsType<PageOpened>(Assert.Single(app.Send(new OpenPage(page, workspace, space, tab, window)))).Page;
        Assert.Equal(new PageState(page, workspace, space, tab, EngineKind.WebKit, PagePhase.Opening, PageLiveState.Blank), opened);
        Assert.Equal([new CreatePage(page, ProfileId(session["spaces"]![0]!), IsPrivate: false, window)], binding.Commands);
        app.Report(engine, new PageCreated(page));
        Assert.Equal(opened with { Phase = PagePhase.Live }, Assert.IsType<PageChanged>(Assert.Single(app.Drain())).Page);

        // A repeated, backwards or stale report changes nothing.
        app.Report(engine, new PageCreated(page));
        app.Report(engine, new PageCreationFailed(page));
        app.Report(engine, new PageClosed(Guid.NewGuid()));
        Assert.Empty(app.Drain());

        // A tab owns one page, an identity names one page, and transient pages have no tab.
        Assert.Equal(new TabAlreadyHasPage(tab, page), Refusal(app, new OpenPage(Guid.NewGuid(), workspace, space, tab, window)));
        Assert.Equal(new DuplicatePage(page), Refusal(app, new OpenPage(page, workspace, space, null, window)));
        app.Send(new OpenPage(Guid.NewGuid(), workspace, space, null, window));
        app.Send(new OpenPage(Guid.NewGuid(), workspace, space, null, window));
        Assert.Equal(new UnknownWorkspace(window), Refusal(app, new OpenPage(Guid.NewGuid(), window, space, null, window)));
        Assert.Equal(new WindowNotOpen(workspace), Refusal(app, new OpenPage(Guid.NewGuid(), workspace, space, null, workspace)));
        Assert.Equal(new UnknownSpace(tab), Refusal(app, new OpenPage(Guid.NewGuid(), workspace, tab, null, window)));

        // Releasing removes the page at once, so its tab can open another,
        // and the engine closes what it holds afterwards.
        Assert.Equal([new PageRemoved(page)], app.Send(new ReleasePage(page, KeepsState: true)));
        Assert.Equal(new ClosePage(page, KeepsState: true), binding.Commands[^1]);
        app.Report(engine, new PageClosed(page));
        Assert.Empty(app.Drain());
        Assert.Equal(new UnknownPage(page), Refusal(app, new ReleasePage(page, KeepsState: false)));
        app.Send(new OpenPage(Guid.NewGuid(), workspace, space, tab, window));

        // A page its engine could not create holds nothing for the engine to close.
        var failed = Guid.NewGuid();
        app.Send(new OpenPage(failed, workspace, SpaceId(session["spaces"]![1]!), null, window));
        app.Report(engine, new PageCreationFailed(failed));
        Assert.Equal(PagePhase.Failed, Assert.IsType<PageChanged>(Assert.Single(app.Drain())).Page.Phase);
        int delivered = binding.Commands.Count;
        app.Send(new ReleasePage(failed, KeepsState: false));
        Assert.Equal(delivered, binding.Commands.Count);
    }

    [Fact]
    public void NoPageOpensInALockedSpaceOrOneBeingDeleted() {
        var session = GuardedSession(withOpenSecondSpace: true);
        var (app, _, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var locked = Identity(session);
        var open = SpaceId(session["spaces"]![1]!);
        var borrowed = TestWorkspaces.Borrow(app, workspace, session["spaces"]![1]!);

        Assert.Equal(new SpaceLocked(locked.Space), Refusal(app, new OpenPage(Guid.NewGuid(), workspace, locked.Space, null, window)));
        Unlock(app.Send, workspace, locked.Space);
        app.Send(new OpenPage(Guid.NewGuid(), workspace, locked.Space, null, window));

        // A Space being deleted opens no page, and a workspace that borrows it
        // closes with the deletion's first step.
        Assert.Contains(new WorkspaceClosed(borrowed), app.Send(new BeginDeletingSpace(workspace, window, open, Guid.NewGuid())));
        Assert.Equal(new SpaceBeingDeleted(open), Refusal(app, new OpenPage(Guid.NewGuid(), workspace, open, null, window)));
        Assert.Equal(new UnknownWorkspace(borrowed), Refusal(app, new OpenPage(Guid.NewGuid(), borrowed, open, null, window)));
        Assert.Single(binding.Commands);
    }

    [Fact]
    public void AClosingWorkspaceTakesItsPagesAndTheirEnginesKeepNothing() {
        var session = TwoSpaceSession();
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var (space, lent) = (session["spaces"]![0]!, session["spaces"]![1]!);
        var borrowed = TestWorkspaces.Borrow(app, workspace, lent);
        var borrowedWindow = Guid.NewGuid();
        app.Send(new OpenWindow(borrowedWindow, borrowed, Saved: false, null, null, [], RestoresTabs: true));
        var (borrowedPage, tabPage, opening) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        app.Send(new OpenPage(borrowedPage, borrowed, SpaceId(lent), null, borrowedWindow));
        app.Send(new OpenPage(tabPage, workspace, SpaceId(space), TabId(space, 0), window));
        app.Report(engine, new PageCreated(borrowedPage));
        app.Report(engine, new PageCreated(tabPage));
        app.Send(new OpenPage(opening, workspace, SpaceId(space), null, window));
        app.Report(engine, new PageCreationFailed(opening));
        _ = app.Drain();

        // An owner intent that stops lending the Space, such as starting to
        // delete it, closes its borrower, and the engine hears to close the
        // borrower's page once the intent returns.
        var lending = app.Send(new BeginDeletingSpace(workspace, window, SpaceId(lent), Guid.NewGuid()));
        Assert.Equal(new ClosePage(borrowedPage, KeepsState: false), binding.Commands[^1]);
        Assert.Equal([new PageRemoved(borrowedPage), new WindowClosed(borrowedWindow), new WorkspaceClosed(borrowed)],
            lending.Where(change => change is PageRemoved or WindowClosed or WorkspaceClosed));

        // Closing a workspace removes every page it has, then its window, and
        // closes on the engine only what the engine still holds.
        var delivered = binding.Commands.Count;
        var closing = app.Send(new CloseWorkspace(workspace));
        Assert.Equal([typeof(PageRemoved), typeof(PageRemoved), typeof(WindowClosed), typeof(WorkspaceClosed)],
            closing.Select(change => change.GetType()));
        Assert.Equal(new[] { tabPage, opening }.Order(), closing.OfType<PageRemoved>().Select(change => change.PageId).Order());
        Assert.Equal([new WindowClosed(window), new WorkspaceClosed(workspace)], closing.Skip(2));
        Assert.Equal([new ClosePage(tabPage, KeepsState: false)], binding.Commands.Skip(delivered));
        Assert.Empty(app.Send(new CloseWorkspace(workspace)));
    }

    [Fact]
    public void APageMovesWithinItsProfileAcrossWorkspacesButNeverIntoAnotherProfile() {
        var session = TwoSpaceSession();
        var (app, _, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var (space, other) = (SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!));
        var (tab, otherTab) = (TabId(session["spaces"]![0]!, 0), TabId(session["spaces"]![1]!, 0));
        var borrowed = TestWorkspaces.Borrow(app, workspace, session["spaces"]![0]!);
        var borrowedWindow = Guid.NewGuid();
        app.Send(new OpenWindow(borrowedWindow, borrowed, Saved: false, null, null, [], RestoresTabs: true));
        var transient = Guid.NewGuid();
        var resident = Guid.NewGuid();
        app.Send(new OpenPage(transient, workspace, space, null, window));
        app.Send(new OpenPage(resident, workspace, space, tab, window));

        // A tab adopting a transient page takes it only while it owns none.
        Assert.Equal(new TabAlreadyHasPage(tab, resident), Refusal(app, new MovePage(transient, workspace, space, tab, window)));
        app.Send(new ReleasePage(resident, KeepsState: false));
        var adopted = Assert.IsType<PageChanged>(Assert.Single(app.Send(new MovePage(transient, workspace, space, tab, window)))).Page;
        Assert.Equal(new PageState(transient, workspace, space, tab, EngineKind.WebKit, PagePhase.Opening, PageLiveState.Blank), adopted);

        // The borrowed workspace shows the same Space in the same profile.
        var moved = Assert.IsType<PageChanged>(Assert.Single(app.Send(new MovePage(transient, borrowed, space, tab, borrowedWindow)))).Page;
        Assert.Equal(borrowed, moved.WorkspaceId);
        Assert.Empty(app.Send(new MovePage(transient, borrowed, space, tab, borrowedWindow)));

        Assert.Equal(new PageProfileMismatch(transient, other),
            Refusal(app, new MovePage(transient, workspace, other, otherTab, window)));
        Assert.Equal(new UnknownPage(resident), Refusal(app, new MovePage(resident, workspace, space, null, window)));
        Assert.Equal(new WindowNotOpen(borrowed), Refusal(app, new MovePage(transient, borrowed, space, tab, borrowed)));
        Assert.Equal(2, binding.Commands.OfType<CreatePage>().Count());
    }

    [Fact]
    public void EachWindowHostsOnePageForATabAndAMovedPageBelongsToItsNewWindow() {
        var session = TwoSpaceSession();
        var (app, _, _, workspace, first) = PageHost(session);
        using var disposal = app;
        var (space, tab) = (SpaceId(session["spaces"]![0]!), TabId(session["spaces"]![0]!, 0));
        var second = Guid.NewGuid();
        app.Send(new OpenWindow(second, workspace, Saved: false, null, null, [], RestoresTabs: true));
        var (firstPage, secondPage, transient) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());

        // Two windows that keep pages of their own, as iPad scenes do, each
        // host a page for the tab; one window hosts only one.
        app.Send(new OpenPage(firstPage, workspace, space, tab, first));
        app.Send(new OpenPage(secondPage, workspace, space, tab, second));
        Assert.Equal(new TabAlreadyHasPage(tab, firstPage), Refusal(app, new OpenPage(Guid.NewGuid(), workspace, space, tab, first)));

        // A page moved into a window takes the tab's place there.
        app.Send(new ReleasePage(secondPage, KeepsState: false));
        app.Send(new OpenPage(transient, workspace, space, null, first));
        app.Send(new MovePage(transient, workspace, space, tab, second));
        Assert.Equal(new TabAlreadyHasPage(tab, transient), Refusal(app, new OpenPage(Guid.NewGuid(), workspace, space, tab, second)));
        Assert.Equal(new TabAlreadyHasPage(tab, transient), Refusal(app, new MovePage(firstPage, workspace, space, tab, second)));
    }

    [Fact]
    public void CommandsReachTheirEngineInOrderAndNeverOnTheStackOfTheCallThatCausedThem() {
        var session = TwoSpaceSession();
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var space = SpaceId(session["spaces"]![0]!);
        var profile = ProfileId(session["spaces"]![0]!);
        var (first, second) = (Guid.NewGuid(), Guid.NewGuid());
        int deliveredWhenNestedSendReturned = -1;
        IReadOnlyList<Change> released = [];
        binding.OnCommand = command => {
            if (command != new CreatePage(first, profile, IsPrivate: false, window)) return;
            // Inside a delivery, an intent and a report only add to the queue.
            app.Send(new OpenPage(second, workspace, space, null, window));
            deliveredWhenNestedSendReturned = binding.Commands.Count;
            app.Report(engine, new PageCreated(first));
            released = app.Send(new ReleasePage(first, KeepsState: false));
        };

        app.Send(new OpenPage(first, workspace, space, null, window));

        Assert.Equal(1, deliveredWhenNestedSendReturned);
        Assert.Equal([
            new CreatePage(first, profile, IsPrivate: false, window),
            new CreatePage(second, profile, IsPrivate: false, window),
            new ClosePage(first, KeepsState: false)
        ], binding.Commands);
        // The report was pending when the release ran, so the release answers
        // it before its own changes.
        Assert.Equal(PagePhase.Live, Assert.IsType<PageChanged>(released[0]).Page.Phase);
        Assert.Empty(app.Drain());
    }

    [Fact]
    public void AnEngineRegistersWithEveryRequiredCapabilityAndOnlyOneIsTheDefault() {
        using var app = new CrestApp();
        var partial = EngineCapability.Required.Skip(1).ToArray();
        Assert.Equal(new EngineLacksCapability(EngineKind.Chromium, EngineCapability.Required[0]), Assert.Throws<Rejected>(
            () => app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, partial, IsDefault: true), _ => { })).Rejection);

        var registered = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.All, IsDefault: false), _ => { });
        Assert.Equal(new EngineAlreadyRegistered(EngineKind.WebKit), Assert.Throws<Rejected>(
            () => app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.All, IsDefault: true), _ => { })).Rejection);
        var session = SavedSession().Document["session"]!;
        var workspace = TestWorkspaces.Open(app, session);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        Assert.Equal(new EngineNotRegistered(), Refusal(app, new OpenPage(Guid.NewGuid(), workspace, SpaceId(session["spaces"]![0]!), null, window)));

        app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: true), _ => { });

        // A binding that is gone frees its engine for another, which may not
        // be a second default.
        app.UnregisterEngine(registered);
        Assert.Equal(new DefaultEngineAlreadyRegistered(EngineKind.Chromium), Assert.Throws<Rejected>(
            () => app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.All, IsDefault: true), _ => { })).Rejection);
        app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.All, IsDefault: false), _ => { });
    }
}
