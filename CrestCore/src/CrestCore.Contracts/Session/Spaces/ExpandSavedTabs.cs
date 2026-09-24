namespace CrestCore.Contracts;

/// Expands or collapses a Space's saved tabs, stamping when that changed so
/// the newest choice wins across devices.
public sealed record ExpandSavedTabs(Guid WorkspaceId, Guid SpaceId, bool IsExpanded) : SessionIntent(WorkspaceId);
