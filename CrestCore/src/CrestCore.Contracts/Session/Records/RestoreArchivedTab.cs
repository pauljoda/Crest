namespace CrestCore.Contracts;

/// Reopens an archived tab as an open tab of its Space and removes its entry
/// from the archive. The window that asked shows it, when that window is open
/// over the workspace.
public sealed record RestoreArchivedTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId);
