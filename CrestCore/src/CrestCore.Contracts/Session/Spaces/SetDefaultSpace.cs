namespace CrestCore.Contracts;

/// Makes a Space the one a launch opens.
public sealed record SetDefaultSpace(Guid WorkspaceId, Guid SpaceId) : SessionIntent(WorkspaceId);
