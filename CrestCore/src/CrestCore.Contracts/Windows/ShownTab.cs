namespace CrestCore.Contracts;

/// The tab a window shows in one Space, or none.
public sealed record ShownTab(Guid SpaceId, Guid? TabId);
