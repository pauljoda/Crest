using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Moves a folder, with every folder, tab and split inside it however deep,
/// to the Space `DestinationSpaceId`, at the top level of the same section
/// there, after what that section holds. Its folders keep their titles, looks,
/// disclosure and tree under identities the core gives them there, and its
/// tabs keep their identities, state and splits. The window then shows the
/// tab it showed before in the Space they left, when the one it showed moved.
/// When this device's link preferences follow moved tabs and a tab moved, it
/// moves to the destination and shows the tab it showed when that moved, or
/// else the first moved tab. Saved with the sync journal before the intent
/// returns. Refused with `AlreadyInSpace` for the Space the folder is in,
/// `UnknownFolder` for a folder that is not there, `TabAlreadyExists` when the
/// destination holds one of its tabs, open or in its archive, and
/// `TabLimitReached`, `PinnedTabsFull` or `FolderLimitReached` when the
/// destination has no room.
public sealed record MoveFolderToSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid FolderId, Guid DestinationSpaceId)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Moves the folder to another Space of this workspace. The issuing window
    /// gives up a moved tab it showed for the one it showed before, and when
    /// the device follows moved tabs it moves to the destination and shows one
    /// there.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        if (DestinationSpaceId == SpaceId) throw new Rejected(new AlreadyInSpace(SpaceId));
        var space = workspace.Editable(turn.Basis, SpaceId);
        var destination = workspace.Editable(turn.Basis, DestinationSpaceId);
        var edited = BrowserTabCollection.Restore(space);
        var receiving = BrowserTabCollection.Restore(destination);
        var moving = edited.TabsInFolder(FolderId).ToHashSet();
        // The edit sees only what it archives itself; the destination's own
        // archive is checked here, as a move to another window checks it.
        if (destination.ArchivedTabs.FirstOrDefault(archived => moving.Contains(archived.Tab.Id)) is { } held)
            throw new Rejected(new TabAlreadyExists(held.Tab.Id));
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var shown = followUp.Window?.Tab(space.Id);
        var fallback = shown is { } active && moving.Contains(active)
            ? followUp.FallbackAfterDismissing(space.Id, active, space.Tabs.Select(tab => tab.Id).Where(id => !moving.Contains(id)).ToHashSet())
            : null;
        var (next, moved) = edited.TransferFolderTo(receiving, FolderId, shown, fallback, turn.Ids, turn.Now);
        edited.PruneSplitMetadata();
        receiving.PruneSplitMetadata();
        followUp.ShowTab(space.Id, next);
        if (workspace.FollowsMovedTabs && moved.Count > 0) {
            var followed = shown is { } showed && moving.Contains(showed) ? showed : moved[0];
            receiving.Tab(followed).Activate(turn.Now);
            followUp.ShowTab(destination.Id, followed).ShowSpace(destination.Id);
        }
        return new(turn.Basis.Replacing(edited.Capture(space), receiving.Capture(destination)), SyncStaging.FolderMove, followUp);
    }

    #endregion
}
