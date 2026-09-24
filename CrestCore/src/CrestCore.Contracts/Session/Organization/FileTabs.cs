namespace CrestCore.Contracts;

/// Moves the tabs and folders a person selected in a window into `FolderId`
/// or to the top level of `Placement`'s section, before the tab `BeforeTabId`
/// or the folder `BeforeFolderId` names, in the order the sidebar lists them.
/// A selected folder moves whole, and a split member brings its split along,
/// unless `LeavesSplits` takes it out. In a section that holds no folders,
/// such as the pinned tabs, the tabs move one by one, refused with
/// `CannotPinSplit` for a split member that stays in its split and with
/// `PinnedTabsFull` when the section cannot hold them all. Saved with the sync
/// journal before the intent returns.
public sealed record FileTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, TabPlacement Placement,
    Guid? FolderId, Guid? BeforeTabId, Guid? BeforeFolderId, bool LeavesSplits) : SessionIntent(WorkspaceId);
