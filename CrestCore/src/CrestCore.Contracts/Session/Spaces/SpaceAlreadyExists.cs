namespace CrestCore.Contracts;

/// The workspace already holds a Space with this identity.
public sealed record SpaceAlreadyExists(Guid SpaceId) : Rejection;
