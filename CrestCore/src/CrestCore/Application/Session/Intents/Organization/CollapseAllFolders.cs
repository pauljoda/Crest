using CrestCore.Application;

namespace CrestCore.Contracts;

/// Collapses every open folder in a Space's sidebar, however deep, as
/// collapsing each would. Groups keep their own state, and every tab stays
/// where it is, loaded or not. A Space with no open folder is left as it is.
public sealed record CollapseAllFolders(Guid WorkspaceId, Guid SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Editable(turn.Basis, SpaceId).Folders.Any(folder => folder.CollapsesWithAll)
            ? workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => edited.CollapseAllFolders(turn.Now))
            : null;

    #endregion
}
