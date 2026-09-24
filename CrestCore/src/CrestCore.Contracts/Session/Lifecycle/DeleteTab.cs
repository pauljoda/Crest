namespace CrestCore.Contracts;

/// Deletes a tab from any section and keeps it in the archive as an open tab.
/// The window that asked returns to the tab it showed before, or to the tab
/// its Space falls back to.
public sealed record DeleteTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId);
