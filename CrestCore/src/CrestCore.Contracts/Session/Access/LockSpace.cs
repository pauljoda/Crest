namespace CrestCore.Contracts;

/// Locks a Space again: every grant for it is revoked, and a request waiting
/// to unlock it is cancelled.
public sealed record LockSpace(Guid SpaceId) : SpaceAccessIntent;
