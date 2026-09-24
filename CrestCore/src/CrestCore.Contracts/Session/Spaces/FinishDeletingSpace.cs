namespace CrestCore.Contracts;

/// Removes a Space whose deletion `OperationId` began, once the platform has
/// erased its profile's data, and saves that before it returns. The Space
/// that takes its place becomes the launch Space when it was one, and the
/// window that asked moves there when it showed the removed one.
public sealed record FinishDeletingSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid OperationId)
    : SessionIntent(WorkspaceId);
