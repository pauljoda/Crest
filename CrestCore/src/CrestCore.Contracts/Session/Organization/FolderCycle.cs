namespace CrestCore.Contracts;

/// The folder would move into itself or into one of its own folders.
public sealed record FolderCycle(Guid FolderId) : Rejection;
