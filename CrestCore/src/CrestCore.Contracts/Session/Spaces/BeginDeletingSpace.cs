namespace CrestCore.Contracts;

/// Starts deleting a Space as the deletion `OperationId` names, and saves
/// that before it returns. The Space and its profile stay exactly as they are
/// until `FinishDeletingSpace` removes them, which the platform sends once it
/// has erased the profile's data. Beginning again with the same operation, as
/// a relaunch does, changes nothing. The window that asked moves to the first
/// Space that stays, when it showed this one. A locked Space may be deleted.
public sealed record BeginDeletingSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid OperationId)
    : SessionIntent(WorkspaceId);
