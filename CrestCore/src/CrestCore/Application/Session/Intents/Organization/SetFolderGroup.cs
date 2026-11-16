using CrestCore.Application;

namespace CrestCore.Contracts;

/// Turns a folder into a group, or a group back into a folder. Only a folder
/// of open tabs at the top level that holds tabs and no folders becomes a
/// group; refused with `CannotBecomeGroup` for any other.
public sealed record SetFolderGroup(Guid WorkspaceId, Guid SpaceId, Guid FolderId, bool IsGroup) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.SetFolderGroup(FolderId, IsGroup));

    #endregion
}
