namespace CrestCore.Contracts;

/// Names a split of two or more tabs. A blank or null name clears it.
public sealed record NameSplit(Guid WorkspaceId, Guid SpaceId, Guid GroupId, string? Name) : SessionIntent(WorkspaceId);
