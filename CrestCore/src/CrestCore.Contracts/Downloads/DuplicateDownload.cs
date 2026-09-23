namespace CrestCore.Contracts;

/// A download with this identity is already recorded.
public sealed record DuplicateDownload() : Rejection;
