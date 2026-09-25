namespace CrestCore.Contracts;

/// Drops the lift on another Space of the workspace, to the end of each tab's
/// own section there, and the window follows it when `Follows`. One tab moves
/// as `MoveTabToSpace` moves it; any other lift as `MoveTabsToSpace` moves it.
/// Refused with `PinnedTabsStayPut` for a lift of several pinned tabs.
public sealed record DropOnSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid DestinationSpaceId,
    bool Follows) : SidebarDrop(WorkspaceId, WindowId, SpaceId, Selection);
