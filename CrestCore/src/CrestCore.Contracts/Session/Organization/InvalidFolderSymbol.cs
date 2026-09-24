namespace CrestCore.Contracts;

/// A folder's symbol is an SF Symbol name or an emoji, never empty and never
/// longer than `MaximumBytes` in UTF-8.
public sealed record InvalidFolderSymbol(int MaximumBytes) : Rejection;
