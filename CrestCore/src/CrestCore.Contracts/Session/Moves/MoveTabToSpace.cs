namespace CrestCore.Contracts;

/// Moves a tab to the Space `DestinationSpaceId`: into `FolderId` or to the
/// top level of `Placement`'s section there, or of the section it is in,
/// before the tab `BeforeTabId` or after the section's last tab. A split
/// member leaves its split. The window that asked shows the tab it showed
/// before in the Space the tab left, when it showed the moved one; when
/// `Follows`, it moves to the destination and shows the moved tab. Saved with
/// the sync journal before the intent returns. Refused with `AlreadyInSpace`
/// for the Space the tab is in, and with `TabLimitReached` or
/// `PinnedTabsFull` when the destination has no room.
public sealed record MoveTabToSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, Guid DestinationSpaceId,
    TabPlacement? Placement, Guid? FolderId, Guid? BeforeTabId, bool Follows) : SessionIntent(WorkspaceId);
