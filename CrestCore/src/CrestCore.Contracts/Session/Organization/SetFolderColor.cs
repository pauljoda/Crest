namespace CrestCore.Contracts;

/// Gives a folder the color its icon wears.
public sealed record SetFolderColor(Guid WorkspaceId, Guid SpaceId, Guid FolderId, BrandColor Color) : SessionIntent(WorkspaceId);
