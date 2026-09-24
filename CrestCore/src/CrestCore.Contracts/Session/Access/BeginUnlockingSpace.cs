namespace CrestCore.Contracts;

/// Starts unlocking a Space of a workspace as the request `RequestId`, which
/// the platform answers once the device owner has authenticated or declined.
/// One request waits at a time. A Space that opens freely, or that this
/// process already unlocked, needs no request and changes nothing.
public sealed record BeginUnlockingSpace(Guid WorkspaceId, Guid SpaceId, Guid RequestId) : SpaceAccessIntent;
