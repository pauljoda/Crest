namespace CrestCore.Contracts;

/// Gives a tab that shows a native view or the Start Page the web address
/// `Url`, titled by its host, so a page can open for it and load there. A tab
/// that already shows a web page keeps its address until its engine reports
/// where the navigation landed, so the intent changes nothing for it. Refused
/// when the workspace, Space or tab is not there, the Space is locked or being
/// deleted, or `Url` is not an absolute address.
public sealed record NavigateTab(Guid WorkspaceId, Guid SpaceId, Guid TabId, string Url) : SessionIntent(WorkspaceId);
