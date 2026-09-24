namespace CrestCore.Contracts;

/// Renames a folder. A blank title names it "Untitled Folder".
public sealed record RenameFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId, string Title) : SessionIntent(WorkspaceId);
