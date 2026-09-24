namespace CrestCore.Contracts;

/// Tints a split of two or more tabs. Null clears the tint.
public sealed record TintSplit(Guid WorkspaceId, Guid SpaceId, Guid GroupId, BrandColor? Tint) : SessionIntent(WorkspaceId);
