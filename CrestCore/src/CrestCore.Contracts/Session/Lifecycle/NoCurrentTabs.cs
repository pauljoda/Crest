namespace CrestCore.Contracts;

/// The Space has no open tab to clear.
public sealed record NoCurrentTabs(Guid SpaceId) : Rejection;
