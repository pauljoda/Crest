using CrestCore.Contracts;

namespace CrestCore.Application;

/// The pages this device hosts: which tab or transient request owns each, the
/// window that hosts it and the engine that hosts it. Never saved or synced.
/// The platform decides when a page opens or goes; the core decides whether it
/// may, and on which engine, and asks the engine to create and close it.
///
/// A window hosts one page for a tab. The Mac's windows over one workspace
/// share one runtime store, so a second window shows the page the first opened
/// and never opens its own; each iPad scene keeps pages of its own, so two
/// scenes showing one tab each host a page for it.
internal sealed class Pages(Device device, Engines engines) {
    #region Variables

    private readonly Dictionary<Guid, Page> open = [];

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

    #endregion

    #region Actions - Reports

    /// Applies what an engine saw happen to one of its pages. A report about a
    /// page the core no longer knows, one another engine hosts, or one that
    /// would move a page backwards changes nothing.
    public void Report(Engine engine, EngineEvent report, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(engine);
        ArgumentNullException.ThrowIfNull(report);
        ArgumentNullException.ThrowIfNull(changes);
        var (pageId, next) = report switch {
            PageCreated created => (created.PageId, PagePhase.Live),
            PageCreationFailed failed => (failed.PageId, PagePhase.Failed),
            PageClosed closed => (closed.PageId, PagePhase.Closed),
            _ => throw new ArgumentOutOfRangeException(nameof(report), report.GetType().Name, "Pages do not handle this report.")
        };
        if (!open.TryGetValue(pageId, out var page) || !ReferenceEquals(page.Engine, engine) || !page.Enter(next)) return;
        changes.Publish(new PageChanged(page.State));
    }

    #endregion

    #region Actions - Rules

    private Page Known(Guid pageId) => open.TryGetValue(pageId, out var page) ? page : throw new Rejected(new UnknownPage(pageId));

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
