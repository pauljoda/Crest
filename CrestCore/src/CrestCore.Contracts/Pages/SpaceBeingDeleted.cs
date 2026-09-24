namespace CrestCore.Contracts;

/// The Space is being deleted, so nothing new may live in its profile.
public sealed record SpaceBeingDeleted(Guid SpaceId) : Rejection;
