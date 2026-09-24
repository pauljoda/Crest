namespace CrestCore.Contracts;

/// Adds a Space after the others, with a profile of its own and one Start
/// Page tab. The core names it and gives it its symbol, accent and look; a
/// private workspace's Space never offers to save passwords. The window that
/// asked shows it, when that window is open over the workspace.
public sealed record CreateSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId) : SessionIntent(WorkspaceId);
