namespace CrestCore.Contracts;

/// Puts the workspace's Spaces in the order `SpaceIds` lists, which names
/// each of them once.
public sealed record ReorderSpaces(Guid WorkspaceId, IReadOnlyList<Guid> SpaceIds) : SessionIntent(WorkspaceId);
