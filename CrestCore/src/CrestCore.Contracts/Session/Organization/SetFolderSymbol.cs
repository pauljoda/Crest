namespace CrestCore.Contracts;

/// Gives a folder its icon: an SF Symbol name or an emoji.
public sealed record SetFolderSymbol(Guid WorkspaceId, Guid SpaceId, Guid FolderId, string Symbol) : SessionIntent(WorkspaceId);
