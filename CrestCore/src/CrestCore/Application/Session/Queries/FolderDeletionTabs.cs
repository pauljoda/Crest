using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The tabs `DeleteFolderAndContents` would delete as the session stands now:
/// every tab the folder and the folders inside it hold, split members
/// included. Refused with `UnknownSpace` or `UnknownFolder` for a Space or
/// folder that is not there.
public sealed record FolderDeletionTabs(Guid WorkspaceId, Guid SpaceId, Guid FolderId) : Query<RemovedTabs> {
    #region Actions - Answering

    internal override RemovedTabs Answer(CrestApp app) {
        var space = app.Device.Workspace(WorkspaceId).Current.KnownSpace(SpaceId);
        return new(BrowserTabCollection.Restore(space).TabsInFolder(FolderId));
    }

    #endregion
}
