namespace CrestCore.Contracts;

/// The folder or tabs cannot go where the edit places them: the section holds
/// no folders, the folder named to hold them is in another section, or the
/// folder or tab named to go before is elsewhere or moves with them.
public sealed record InvalidFolderPlacement : Rejection;
