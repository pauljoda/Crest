namespace CrestCore.Contracts;

/// A Quick Window's or Peek's page, `PageId`, became the tab `TabId`. When
/// `AdoptsPage`, the tab takes the live page, which the platform moves to the
/// tab's window; otherwise the page goes and the tab opens its own.
public sealed record TransientPagePromoted(Guid WorkspaceId, Guid PageId, Guid TabId, bool AdoptsPage) : Change;
