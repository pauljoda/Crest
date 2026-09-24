namespace CrestCore.Contracts;

/// The workspace holds no Space with this identity.
public sealed record UnknownSpace(Guid SpaceId) : Rejection;
