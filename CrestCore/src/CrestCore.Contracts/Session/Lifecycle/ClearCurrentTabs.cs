namespace CrestCore.Contracts;

/// Archives every open tab of a Space and keeps its saved and pinned tabs.
/// The window that asked shows the tab its Space falls back to. Refused with
/// `NoCurrentTabs` when the Space has no open tab.
public sealed record ClearCurrentTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId) : SessionIntent(WorkspaceId);
