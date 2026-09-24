namespace CrestCore.Contracts;

/// Deletes the tabs a person selected in a window, saved and pinned ones
/// included, into the archive as open tabs. The window then shows the tab it
/// showed before, when the one it showed was deleted, or none. It is saved
/// with the sync journal, as a deletion, before the intent returns.
public sealed record DeleteTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection) : SessionIntent(WorkspaceId);
