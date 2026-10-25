using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Deletes a folder. Its tabs and folders move up into its parent, or to the
/// top level of its section. A live folder archives its managed tabs and stays
/// dismissed until explicitly added again.
public sealed record DeleteFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var folder = space.Folders.FirstOrDefault(item => item.Id == FolderId);
        if (folder?.Source is null)
            return workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Deletion, edited => edited.DeleteFolder(FolderId, turn.Now));
        var edited = BrowserTabCollection.Restore(space);
        edited.DismissTabs(space.Tabs.Where(tab => tab.FolderId == FolderId).Select(tab => tab.Id).ToArray(),
            null, null, turn.Now, deleting: true, ensureSelection: false, resetArchivePlacement: true);
        edited.DeleteFolder(FolderId, turn.Now);
        var next = edited.Capture(space);
        if (folder.Source == LiveFolderSource.GitHubPullRequests)
            next = next with { Settings = next.Settings with { IsGitHubFolderDismissed = true } };
        return new(turn.Basis.Replacing(next), SyncStaging.Deletion);
    }

    #endregion
}
