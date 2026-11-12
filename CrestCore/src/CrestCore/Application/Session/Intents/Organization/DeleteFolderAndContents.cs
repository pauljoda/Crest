using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Deletes a folder with every folder inside it, and each tab they hold,
/// split members included, into the archive as open tabs, where the person can
/// restore them. When the window that asked showed one of them, it shows the
/// tab it showed before that, or none; a window on another tab, or on none,
/// stays where it is. It is saved with the sync
/// journal, as a deletion, before the intent returns. Refused with
/// `UnknownFolder` for a folder that is not there.
public sealed record DeleteFolderAndContents(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid FolderId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var edited = BrowserTabCollection.Restore(space);
        var deleting = edited.TabsInFolder(FolderId).ToHashSet();
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var shown = followUp.Window?.Tab(space.Id);
        var fallback = shown is { } active && deleting.Contains(active)
            ? followUp.FallbackAfterDismissing(space.Id, active, space.Tabs.Select(tab => tab.Id).Where(id => !deleting.Contains(id)).ToHashSet())
            : null;
        followUp.ShowTab(space.Id, edited.DeleteFolderAndContents(FolderId, shown, fallback, turn.Now));
        edited.PruneSplitMetadata();
        return new(turn.Basis.Replacing(edited.Capture(space)), SyncStaging.BatchDeletion, followUp);
    }

    #endregion
}
