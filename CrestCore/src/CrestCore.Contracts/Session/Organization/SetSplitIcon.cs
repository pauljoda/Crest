namespace CrestCore.Contracts;

/// Gives a split of two or more tabs its icon: an SF Symbol name or an emoji
/// spelling. Null clears it.
public sealed record SetSplitIcon(Guid WorkspaceId, Guid SpaceId, Guid GroupId, string? Symbol) : SessionIntent(WorkspaceId);
