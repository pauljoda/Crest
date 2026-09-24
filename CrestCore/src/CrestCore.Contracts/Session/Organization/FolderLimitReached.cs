namespace CrestCore.Contracts;

/// The Space already holds `Limit` folders.
public sealed record FolderLimitReached(int Limit) : Rejection;
