using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Moves the tabs a person selected in a window to the Space
/// `DestinationSpaceId`, each to the end of its own section there, in the
/// order the sidebar lists them. The window then shows the tab it showed
/// before in the Space they left, when the one it showed moved. When this
/// device's link preferences follow moved tabs, it moves to the destination
/// and shows the tab it showed when that moved, or else the first moved tab.
/// Refused with `AlreadyInSpace` for the Space they are in,
/// `CannotMoveSplitAcrossSpaces` for a split member, and `PinnedTabsFull` when
/// the destination cannot hold them all.
public sealed record MoveTabsToSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection, Guid DestinationSpaceId)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// The window gives up its shown tab when it moved, and moves to the
    /// destination when the device follows moved tabs there.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var batch = workspace.Selecting(turn.Basis, WindowId, SpaceId, Selection);
        if (DestinationSpaceId == SpaceId) throw new Rejected(new AlreadyInSpace(SpaceId));
        var destination = workspace.Editable(turn.Basis, DestinationSpaceId);
        var receiving = BrowserTabCollection.Restore(destination);
        var follows = workspace.FollowsMovedTabs;
        var (shown, shownThere) = batch.Edited.MoveSelected(batch.Selected, receiving, batch.Shown, batch.Fallback(),
            batch.FollowUp.Window?.Tab(destination.Id), follows, turn.Now);
        receiving.PruneSplitMetadata();
        batch.FollowUp.ShowTab(batch.Space.Id, shown).ShowTab(destination.Id, shownThere);
        if (follows) batch.FollowUp.ShowSpace(destination.Id);
        return batch.Result(turn.Basis, SyncStaging.Batch, alsoEdited: receiving.Capture(destination));
    }

    #endregion
}
