namespace CrestCore.Contracts;

/// The intent names a workspace that is not attached to this device.
public sealed record UnknownWorkspace(Guid WorkspaceId) : Rejection;
