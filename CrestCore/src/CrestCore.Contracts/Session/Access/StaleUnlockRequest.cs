namespace CrestCore.Contracts;

/// The request this answer finishes is no longer the one pending: a lock
/// cancelled it, it already finished, or it was for another Space.
public sealed record StaleUnlockRequest(Guid RequestId) : Rejection;
