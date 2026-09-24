namespace CrestCore.Contracts;

/// The Space already holds a folder with this identity.
public sealed record FolderAlreadyExists(Guid FolderId) : Rejection;
