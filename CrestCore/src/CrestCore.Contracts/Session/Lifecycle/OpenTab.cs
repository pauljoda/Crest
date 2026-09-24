namespace CrestCore.Contracts;

/// Opens a tab, `TabId`, showing `Content` in `Placement`'s section of a
/// Space: after the tab `AfterTabId` names and outside its split, or where its
/// section puts a new tab. When `Shows`, the window that asked shows the tab
/// and its Space. Refused with `TabLimitReached` or `PinnedTabsFull` when the
/// Space or the section is full, and with `UnsupportedAddress` for an address
/// a page cannot load.
public sealed record OpenTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, TabContent Content, TabPlacement Placement,
    Guid? AfterTabId, bool Shows) : SessionIntent(WorkspaceId);
