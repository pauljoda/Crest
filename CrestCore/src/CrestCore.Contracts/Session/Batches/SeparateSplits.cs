namespace CrestCore.Contracts;

/// Dissolves every split the tabs a person selected in a window belong to.
public sealed record SeparateSplits(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection) : SessionIntent(WorkspaceId);
