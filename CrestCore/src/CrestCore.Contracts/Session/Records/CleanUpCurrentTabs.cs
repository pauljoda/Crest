namespace CrestCore.Contracts;

/// Moves the open tabs of a Space that went unused for longer than its
/// cleanup lifetime to its archive, keeping every tab a window shows or a
/// saved window will show. Without a Space it cleans up every Space that is
/// not being deleted, locked or not, since cleanup reveals nothing.
public sealed record CleanUpCurrentTabs(Guid WorkspaceId, Guid? SpaceId) : SessionIntent(WorkspaceId);
