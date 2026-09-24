namespace CrestCore.Contracts;

/// Moves the tabs a person selected in a window to the Space
/// `DestinationSpaceId`, each to the end of its own section there, in the
/// order the sidebar lists them. The window then shows the tab it showed
/// before in the Space they left, when the one it showed moved. When `Follows`,
/// it moves to the destination and shows the tab it showed when that moved, or
/// else the first moved tab. Refused with `AlreadyInSpace` for the Space they
/// are in, `CannotMoveSplitAcrossSpaces` for a split member, and
/// `PinnedTabsFull` when the destination cannot hold them all.
public sealed record MoveTabsToSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid DestinationSpaceId,
    bool Follows) : SessionIntent(WorkspaceId);
