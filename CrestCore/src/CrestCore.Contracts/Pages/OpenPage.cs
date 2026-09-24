namespace CrestCore.Contracts;

/// Opens a page for a tab, or for a transient request when `TabId` is null, in
/// a Space of a workspace attached to this device, hosted by an open window.
/// The page opens on the default engine, which is asked to create it. Refused
/// when the workspace, Space or window is not there, the Space is locked or
/// being deleted, the window already hosts a page for the tab, or no engine is
/// the default.
public sealed record OpenPage(Guid PageId, Guid WorkspaceId, Guid SpaceId, Guid? TabId, Guid WindowId) : PageIntent;
