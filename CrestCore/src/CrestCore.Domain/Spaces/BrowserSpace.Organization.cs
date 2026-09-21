namespace CrestCore.Domain;

public sealed partial class BrowserSpace {
    #region Variables

    public const int MaximumSplitMembers = BrowserTabCollection.MaximumSplitMembers;

    #endregion

    #region Actions - Split membership

    private void NormalizeSplits(DateTimeOffset now) => collection.NormalizeSplits(now);

    private void RepairSplitMembership() => collection.RepairSplitMembership();

    public SplitJoin JoinSplit(TabId source, TabId target, int? index, IIdSource ids, DateTimeOffset now) { EnsureAccessible(); return collection.JoinSplit(source, target, index, ids, now); }

    public void LeaveSplit(TabId id, DateTimeOffset now) { EnsureAccessible(); collection.LeaveSplit(id, now); }

    #endregion

    #region Actions - Folders

    public void AddFolder(FolderId id, string name, TabPlacement location = TabPlacement.Saved, FolderId? parent = null) { EnsureAccessible(); collection.AddFolder(id, name, location, parent); }

    public void RenameFolder(FolderId id, string name) { EnsureAccessible(); collection.RenameFolder(id, name); }

    public void CollapseFolder(FolderId id, bool collapsed, DateTimeOffset now) { EnsureAccessible(); collection.CollapseFolder(id, collapsed, now); }

    public void DeleteFolder(FolderId id, DateTimeOffset now) { EnsureAccessible(); collection.DeleteFolder(id, now); }

    public void FileTabs(IReadOnlyCollection<TabId> requested, TabPlacement location, FolderId? folder,
        DateTimeOffset now, TabId? before = null, FolderId? beforeFolder = null, bool detachSplitMembers = false) { EnsureAccessible(); collection.FileTabs(requested, location, folder, now, before, beforeFolder, detachSplitMembers); }

    public void MoveFolder(FolderId id, TabPlacement? location, FolderId? parent, DateTimeOffset now,
        FolderId? beforeFolder = null, TabId? beforeTab = null) { EnsureAccessible(); collection.MoveFolder(id, location, parent, now, beforeFolder, beforeTab); }

    #endregion

    #region Actions - Tabs

    public BrowserTab DuplicateTab(TabId id, IIdSource ids, DateTimeOffset now) { EnsureAccessible(); return collection.DuplicateTab(id, ids, now); }

    #endregion

    #region Mutators

    public IReadOnlyList<BrowserTab> SplitMembers(TabId id) => collection.SplitMembers(id);

    #endregion
}
