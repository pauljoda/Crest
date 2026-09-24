using CrestCore.Contracts;

namespace CrestCore.Application;

/// One page this device hosts: its owner, the window that hosts it, the engine
/// that hosts it and where it stands there. Its engine page lives in the
/// profile of the Space it opened in, so the page only ever moves between
/// Spaces of that profile.
internal sealed class Page {
    #region Variables

    public Guid Id { get; }
    public Engine Engine { get; }
    public Guid ProfileId { get; }

    public Guid WorkspaceId { get; private set; }
    public Guid SpaceId { get; private set; }

    /// The tab that owns the page, or null for a Quick Window or Peek page.
    public Guid? TabId { get; private set; }

    /// The window that hosts the page. A window that shares its pages with
    /// others shows this page without owning it.
    public Guid WindowId { get; private set; }

    public PagePhase Phase { get; private set; } = PagePhase.Opening;

    public PageState State => new(Id, WorkspaceId, SpaceId, TabId, Engine.Kind, Phase);

    #endregion

    #region Constructors

    public Page(Guid id, Engine engine, Guid profileId, Guid workspaceId, Guid spaceId, Guid? tabId, Guid windowId) {
        Id = id;
        Engine = engine;
        ProfileId = profileId;
        WorkspaceId = workspaceId;
        SpaceId = spaceId;
        TabId = tabId;
        WindowId = windowId;
    }

    #endregion

    #region Actions - Lifecycle

    /// Moves the page to `next` when it may follow the phase the page is in,
    /// and answers whether it did.
    public bool Enter(PagePhase next) {
        if (!next.Follows(Phase)) return false;
        Phase = next;
        return true;
    }

    /// Gives the page a new owner in a Space of its profile, hosted by `windowId`.
    public void Move(Guid workspaceId, Guid spaceId, Guid? tabId, Guid windowId) {
        WorkspaceId = workspaceId;
        SpaceId = spaceId;
        TabId = tabId;
        WindowId = windowId;
    }

    #endregion
}
