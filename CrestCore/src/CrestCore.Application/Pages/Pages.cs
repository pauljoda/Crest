using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The pages this device hosts: which tab or transient request owns each, the
/// window that hosts it, the engine that hosts it and the live state its
/// engine reports. Never saved or synced. The platform decides when a page
/// opens or goes; the core decides whether it may, and on which engine, and
/// asks the engine to create, load and close it.
///
/// A window hosts one page for a tab. The Mac's windows over one workspace
/// share one runtime store, so a second window shows the page the first opened
/// and never opens its own; each iPad scene keeps pages of its own, so two
/// scenes showing one tab each host a page for it.
///
/// A page's report is stamped with the core's `clock`, and a visit it records
/// takes its identity from `ids`.
internal sealed class Pages(Device device, Engines engines, IClock clock, IIdSource ids) {
    #region Variables

    private readonly Dictionary<Guid, Page> open = [];

    /// Whether the engine new pages open on shows internal pages, such as an
    /// engine's settings.
    public bool OpensInternalPages => engines.Default?.Supports(EngineCapability.InternalPages) == true;

    #endregion

    #region Actions - Intents

    /// Runs one page intent, publishing what it changed to `changes` and
    /// handing the engine commands it causes to `issue`, which delivers them
    /// once the core lets go of its lock.
    public void Handle(PageIntent intent, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(changes);
        ArgumentNullException.ThrowIfNull(issue);
        switch (intent) {
            case OpenPage opening: Open(opening, changes, issue); break;
            case MovePage moving: Move(moving, changes); break;
            case ReleasePage releasing: Release(releasing, changes, issue); break;
            case Navigate navigation: Load(navigation, changes, issue); break;
            case LeavePageFailure leaving: LeaveFailure(leaving, changes); break;
            default: throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "Pages do not handle this intent.");
        }
    }

    private void Open(OpenPage intent, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (open.ContainsKey(intent.PageId)) throw new Rejected(new DuplicatePage(intent.PageId));
        var workspace = device.Workspace(intent.WorkspaceId);
        device.Opened(intent.WindowId);
        var space = Hosting(workspace, intent.SpaceId);
        RequireUnowned(intent.WorkspaceId, intent.WindowId, intent.TabId, moving: null);
        var engine = engines.Default ?? throw new Rejected(new EngineNotRegistered());
        var page = new Page(intent.PageId, engine, space.ProfileId, intent.WorkspaceId, space.Id, intent.TabId, intent.WindowId);
        open[page.Id] = page;
        changes.Publish(new PageOpened(page.State));
        issue(engine, new CreatePage(page.Id, page.ProfileId, workspace.IsPrivateBrowsing));
    }

    private void Move(MovePage intent, ChangeFeed changes) {
        var page = Known(intent.PageId);
        var workspace = device.Workspace(intent.WorkspaceId);
        device.Opened(intent.WindowId);
        var space = Hosting(workspace, intent.SpaceId);
        if (space.ProfileId != page.ProfileId) throw new Rejected(new PageProfileMismatch(page.Id, space.Id));
        RequireUnowned(intent.WorkspaceId, intent.WindowId, intent.TabId, moving: page);
        var before = page.State;
        page.Move(intent.WorkspaceId, space.Id, intent.TabId, intent.WindowId);
        if (page.State != before) changes.Publish(new PageChanged(page.State));
    }

    /// The page is gone at once, so its tab may open another straight away;
    /// the engine closes what it still holds afterwards.
    private void Release(ReleasePage intent, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var page = Known(intent.PageId);
        open.Remove(page.Id);
        changes.Publish(new PageRemoved(page.Id));
        if (page.Phase.HoldsEnginePage) issue(page.Engine, new ClosePage(page.Id, intent.KeepsState));
    }

    /// Resolves what the person asked for by the address rules of the page's
    /// Space and engine, shows the page heading there at once, and asks its
    /// engine to load it.
    private void Load(Navigate intent, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var page = Known(intent.PageId);
        if (!page.Phase.HoldsEnginePage) throw new Rejected(new PageNotLoadable(page.Id));
        var space = Hosting(device.Workspace(page.WorkspaceId), page.SpaceId);
        var url = AddressResolution.Loading(intent.Input, space.Settings.BrowsingPreferences,
            page.Engine.Supports(EngineCapability.InternalPages));
        Update(page, changes, () => page.Load(url));
        issue(page.Engine, new LoadPage(page.Id, url));
    }

    private void LeaveFailure(LeavePageFailure intent, ChangeFeed changes) {
        var page = Known(intent.PageId);
        Update(page, changes, page.LeaveFailure);
    }

    #endregion

    #region Actions - Queries

    /// The live state of the page that shows `tabId` of a workspace in
    /// `windowId`, or in another window of the workspace when that window
    /// hosts none, or null when no page shows the tab.
    public PageLiveState? Showing(Guid workspaceId, Guid windowId, Guid tabId) {
        PageLiveState? elsewhere = null;
        foreach (var page in open.Values) {
            if (page.WorkspaceId != workspaceId || page.TabId != tabId || !page.Phase.HoldsEnginePage) continue;
            if (page.WindowId == windowId) return page.Live;
            elsewhere ??= page.Live;
        }
        return elsewhere;
    }

    #endregion

    #region Actions - Reports

    /// Applies what an engine saw happen to one of its pages. A report about a
    /// page the core no longer knows, one another engine hosts, or one that
    /// would move a page backwards changes nothing. What the engine shows, a
    /// failure and a commit that ends it change the page's live state, which
    /// is published only when it differs. A finished navigation is recorded
    /// once per document in the Space the page lives in, and an icon reported
    /// for a recorded document goes to the page's tab; either waits while a
    /// transaction holds the workspace's session.
    public void Report(Engine engine, EngineEvent report, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(engine);
        ArgumentNullException.ThrowIfNull(report);
        ArgumentNullException.ThrowIfNull(changes);
        var pageId = report switch {
            PageCreated created => created.PageId,
            PageCreationFailed failed => failed.PageId,
            PageClosed closed => closed.PageId,
            NavigationStarted started => started.PageId,
            NavigationCommitted committed => committed.PageId,
            NavigationFinished finished => finished.PageId,
            NavigationFailed failed => failed.PageId,
            PageIconChanged icon => icon.PageId,
            PageStateChanged state => state.PageId,
            _ => throw new ArgumentOutOfRangeException(nameof(report), report.GetType().Name, "Pages do not handle this report.")
        };
        if (!open.TryGetValue(pageId, out var page) || !ReferenceEquals(page.Engine, engine)) return;
        switch (report) {
            case PageCreated: Enter(page, PagePhase.Live, changes); break;
            case PageCreationFailed: Enter(page, PagePhase.Failed, changes); break;
            case PageClosed: Enter(page, PagePhase.Closed, changes); break;
            // Nothing is recorded until the navigation finishes.
            case NavigationStarted: break;
            case NavigationCommitted committed:
                Update(page, changes, () => page.Commit(committed.Url, committed.SameDocument));
                break;
            case NavigationFinished finished when page.Finish(finished.Url):
                Edit(page, new NavigationRecord(page.Id, page.SpaceId, clock.Now, page.TabId, finished.Url, finished.Title, page.Icon,
                    ids.Next()), changes);
                break;
            case NavigationFinished: break;
            case NavigationFailed failed: Update(page, changes, () => page.Fail(failed.Failure)); break;
            case PageIconChanged reported when page.ShowIcon(new(reported.Url, reported.Accent)) && page.TabId is { } tabId:
                Edit(page, new IconAdoption(page.Id, page.SpaceId, clock.Now, tabId, page.Icon!), changes);
                break;
            case PageIconChanged: break;
            case PageStateChanged reported: Update(page, changes, () => page.Show(reported.Snapshot)); break;
        }
    }

    /// Applies `update` to the page, and publishes the page when that changed
    /// what readers see of it.
    private static void Update(Page page, ChangeFeed changes, Action update) {
        var before = page.State;
        update();
        if (page.State != before) changes.Publish(new PageChanged(page.State));
    }

    private static void Enter(Page page, PagePhase next, ChangeFeed changes) {
        if (page.Enter(next)) changes.Publish(new PageChanged(page.State));
    }

    /// Applies a page's edit to the session of the workspace it lives in; a
    /// workspace that is gone takes nothing.
    private void Edit(Page page, PageEdit edit, ChangeFeed changes) {
        if (device.Attached(page.WorkspaceId) is not { } workspace) return;
        foreach (var change in workspace.Apply(edit)) changes.Publish(change);
    }

    #endregion

    #region Actions - Rules

    private Page Known(Guid pageId) => open.TryGetValue(pageId, out var page) ? page : throw new Rejected(new UnknownPage(pageId));

    /// The Quick Window or Peek page `pageId` names, or null when this device
    /// hosts no such page.
    public TransientPage? Transient(Guid pageId) => open.TryGetValue(pageId, out var page) && page.TabId is null
        ? new(page.Id, page.WorkspaceId, page.SpaceId, page.ProfileId, page.Engine.Supports(EngineCapability.WorkspaceTransfer))
        : null;

    /// The Space a page may live in: one the workspace holds, that is not
    /// being deleted, here or in the workspace a borrowed one borrows from, and
    /// that this process may show.
    private static SpaceState Hosting(NativeSessionAuthority workspace, Guid spaceId) {
        var space = workspace.Current.Spaces.FirstOrDefault(space => space.Id == spaceId) ?? throw new Rejected(new UnknownSpace(spaceId));
        if (workspace.IsDeleting(spaceId)) throw new Rejected(new SpaceBeingDeleted(spaceId));
        if (workspace.IsLocked(space)) throw new Rejected(new SpaceLocked(spaceId));
        return space;
    }

    /// A window hosts one page for a tab at a time. Whether the workspace holds
    /// the tab is not checked yet: selection can present a tab before the
    /// core's session has it, and an `UnknownTab` rejection arrives with the
    /// session intents.
    private void RequireUnowned(Guid workspaceId, Guid windowId, Guid? tabId, Page? moving) {
        if (tabId is not { } tab) return;
        if (open.Values.FirstOrDefault(page => page != moving && page.WorkspaceId == workspaceId && page.WindowId == windowId
            && page.TabId == tab) is { } owner)
            throw new Rejected(new TabAlreadyHasPage(tab, owner.Id));
    }

    #endregion
}
