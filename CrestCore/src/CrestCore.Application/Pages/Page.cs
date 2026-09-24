using CrestCore.Contracts;

namespace CrestCore.Application;

/// One page this device hosts: its owner, the engine that hosts it and where
/// it stands there. Its engine page lives in the profile of the Space it
/// opened in, so the page only ever moves between Spaces of that profile.
internal sealed class Page {
    #region Variables

    public Guid Id { get; }
    public Engine Engine { get; }
    public Guid ProfileId { get; }

    /// The window the page was opened from. Windows share their pages, so a
    /// window that shows it later claims it with the engine, not here.
    public Guid OpenedFrom { get; }

    public Guid WorkspaceId { get; private set; }
    public Guid SpaceId { get; private set; }

    /// The tab that owns the page, or null for a Quick Window or Peek page.
    public Guid? TabId { get; private set; }

    public PagePhase Phase { get; private set; } = PagePhase.Opening;

    public PageState State => new(Id, WorkspaceId, SpaceId, TabId, Engine.Kind, Phase);

    #endregion

    #region Constructors

    public Page(Guid id, Engine engine, Guid profileId, Guid openedFrom, Guid workspaceId, Guid spaceId, Guid? tabId) {
        Id = id;
        Engine = engine;
        ProfileId = profileId;
        OpenedFrom = openedFrom;
        WorkspaceId = workspaceId;
        SpaceId = spaceId;
        TabId = tabId;
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

    /// Gives the page a new owner in a Space of its profile.
    public void Move(Guid workspaceId, Guid spaceId, Guid? tabId) {
        WorkspaceId = workspaceId;
        SpaceId = spaceId;
        TabId = tabId;
    }

    #endregion
}
