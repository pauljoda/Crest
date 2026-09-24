namespace CrestCore.Contracts;

/// Closes a tab the way its section closes one: an open tab is archived, and
/// a saved or pinned tab keeps its place and only puts its page away, back at
/// its saved address when the app's preferences say so. A window that showed
/// the tab returns to the tab it showed before. Refused with `LastStartPage`
/// for the Start Page when it is its Space's only tab, which leaves only the
/// window to close.
public sealed record CloseTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId);
