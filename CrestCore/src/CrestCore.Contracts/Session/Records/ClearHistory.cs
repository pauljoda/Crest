namespace CrestCore.Contracts;

/// Removes every address a Space's history holds. Without a Space it clears
/// every Space this process may read, passing over one that is locked or being
/// deleted.
public sealed record ClearHistory(Guid WorkspaceId, Guid? SpaceId) : SessionIntent(WorkspaceId);
