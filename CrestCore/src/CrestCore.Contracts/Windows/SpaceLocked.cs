namespace CrestCore.Contracts;

/// The Space is locked, and this process holds no grant to read or change it.
public sealed record SpaceLocked(Guid SpaceId) : Rejection;
