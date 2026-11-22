using CrestCore.Application;

namespace CrestCore.Contracts;

/// Creates a folder in a Space's saved or open section, or inside `ParentId`,
/// whose section it shares. A blank title names it "New Folder". The tabs
/// `TabIds` names move into it in the same edit, so a folder nobody asked to
/// see empty is never published, and one whose tabs cannot move is never made.
/// A split member brings its split along, unless `LeavesSplits` takes it out.
/// With `IsGroup` it makes a group, which sits at the top level of the open
/// tabs, refused with `InvalidFolderPlacement` anywhere else and with
/// `CannotBecomeGroup` when `TabIds` names no tab.
public sealed record CreateFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId, TabPlacement Placement, Guid? ParentId,
    string? Title, BrandColor? Color, string? Symbol, IReadOnlyList<Guid> TabIds, bool LeavesSplits, bool IsGroup = false)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Creates the folder and files its tabs in one edit.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Creation, edited => {
            if (IsGroup && TabIds.Count == 0) throw new Rejected(new CannotBecomeGroup(FolderId));
            edited.AddFolder(FolderId, NativeSessionAuthority.FolderTitle(Title), Placement, ParentId, IsGroup);
            if (Color is { } color) edited.SetFolderColor(FolderId, color);
            if (Symbol is { } symbol) edited.SetFolderSymbol(FolderId, symbol);
            if (TabIds.Count > 0)
                edited.FileTabs(TabIds, Placement, FolderId, turn.Now, null, null, LeavesSplits);
        });

    #endregion
}
