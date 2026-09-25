namespace CrestCore.Contracts;

/// Drops the lift on the open tab `TabId`, putting that tab and then the lift
/// into a new open-tabs folder in its place, named "New Folder" in the default
/// folder color. One tab goes in as `CreateFolder` puts it, leaving its split;
/// any other lift as `FolderTabsAround` does. Refused with
/// `InvalidFolderPlacement` when `TabId` is not an open tab at the top level,
/// or is in a split or the lift, or is a Start Page.
public sealed record DropAroundTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid TabId)
    : SidebarDrop(WorkspaceId, WindowId, SpaceId, Selection);
