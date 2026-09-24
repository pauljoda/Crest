namespace CrestCore.Contracts;

/// Sets whether a Space opens freely or asks the device owner first. Asking
/// for authentication is always allowed; letting a locked Space open freely
/// takes the grant that unlocking it gives.
public sealed record SetSpaceAccess(Guid WorkspaceId, Guid SpaceId, SpaceAccessPolicy Policy) : SessionIntent(WorkspaceId);
