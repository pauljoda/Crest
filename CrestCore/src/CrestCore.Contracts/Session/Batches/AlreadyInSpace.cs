namespace CrestCore.Contracts;

/// The tabs would move to the Space `SpaceId`, which already holds them.
public sealed record AlreadyInSpace(Guid SpaceId) : Rejection;
