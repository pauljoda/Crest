namespace CrestCore.Contracts;

/// Keeps a Quick Window's or Peek's page, `PageId`, as a new tab of a Space
/// in `Placement`'s section, after the tab the window that asked shows there.
/// The core gives the tab its identity and the address the page shows, and
/// that window shows it and its Space. The tab takes the page itself when the
/// page's engine can move it between windows and the page already lives in
/// that Space; the core says which in `TransientPagePromoted`. Refused when
/// the page was already kept or archived, when its own Space no longer keeps
/// its profile, and when either Space is locked or being deleted.
public sealed record PromoteTransientPage(Guid WorkspaceId, Guid WindowId, Guid PageId, Guid SpaceId, TabPlacement Placement)
    : SessionIntent(WorkspaceId);
