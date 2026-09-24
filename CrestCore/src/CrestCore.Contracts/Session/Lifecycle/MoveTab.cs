namespace CrestCore.Contracts;

/// Moves a tab into `FolderId`, or to the top level of `Placement`'s section,
/// before the tab `BeforeTabId` names or after the section's last tab. A split
/// member keeps its split where the section holds splits, unless `LeavesSplit`
/// takes it out. Refused with `PinnedTabsFull` for a full section,
/// `CannotPinSplit` for a split member moving where no split can go without
/// leaving its split, and `UnknownFolder` or `InvalidFolderPlacement` for a
/// folder that is not there or not in the section.
public sealed record MoveTab(Guid WorkspaceId, Guid SpaceId, Guid TabId, TabPlacement Placement, Guid? FolderId, Guid? BeforeTabId,
    bool LeavesSplit) : SessionIntent(WorkspaceId);
