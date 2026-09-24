namespace CrestCore.Contracts;

/// Gives a tab that shows a native view or the Start Page the web address
/// `Input` names, resolved by its Space's address rules as `Navigate` resolves
/// one and titled by its host, so a page can open for it and load there. A
/// tab that already shows a web page keeps its address until its engine
/// reports where the navigation landed, so the intent changes nothing for it.
/// Refused when the workspace, Space or tab is not there, the Space is locked
/// or being deleted, or `Input` names nothing a page can load, as blank input
/// does.
public sealed record NavigateTab(Guid WorkspaceId, Guid SpaceId, Guid TabId, string Input) : SessionIntent(WorkspaceId);
