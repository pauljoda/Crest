namespace CrestCore.Contracts;

/// The folder, or the deepest folder inside it, would sit `Limit` levels deep
/// or deeper.
public sealed record FolderDepthLimitReached(int Limit) : Rejection;
