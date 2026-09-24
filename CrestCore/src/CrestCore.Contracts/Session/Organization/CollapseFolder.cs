namespace CrestCore.Contracts;

/// Collapses a folder in the sidebar, or expands it.
public sealed record CollapseFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId, bool Collapsed) : SessionIntent(WorkspaceId);
