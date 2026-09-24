namespace CrestCore.Contracts;

/// The core recorded a page's finished navigation to `Url` in a Space: the
/// tab that owns the page, when it has one, shows the address and the page's
/// title, and the Space's history holds a visit when the address is one
/// history keeps. A Quick Window or Peek page has no tab.
public sealed record NavigationRecorded(Guid PageId, Guid WorkspaceId, Guid SpaceId, Guid? TabId, string Url) : Change;
