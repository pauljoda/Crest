namespace CrestCore.Contracts;

/// Another change to the workspace is being saved. The intent changed nothing
/// and may be sent again.
public sealed record WorkspaceBusy(Guid WorkspaceId) : Rejection;
