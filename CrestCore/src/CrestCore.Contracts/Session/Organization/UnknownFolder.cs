namespace CrestCore.Contracts;

/// The Space holds no folder with this identity.
public sealed record UnknownFolder(Guid FolderId) : Rejection;
