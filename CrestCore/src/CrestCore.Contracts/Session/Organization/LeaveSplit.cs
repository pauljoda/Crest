namespace CrestCore.Contracts;

/// Takes a tab out of its split, after the split's last member. A split left
/// with one member ends.
public sealed record LeaveSplit(Guid WorkspaceId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId);
