namespace CrestCore.Contracts;

/// Ends a split. Its tabs stay where they are.
public sealed record DissolveSplit(Guid WorkspaceId, Guid SpaceId, Guid GroupId) : SessionIntent(WorkspaceId);
