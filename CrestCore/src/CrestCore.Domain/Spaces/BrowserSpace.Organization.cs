namespace CrestCore.Domain;

public sealed partial class BrowserSpace {
    #region Variables

    public const int MaximumSplitMembers = BrowserTabCollection.MaximumSplitMembers;

    #endregion

    #region Actions - Split membership

    private void NormalizeSplits(DateTimeOffset now) => collection.NormalizeSplits(now);

    private void RepairSplitMembership() => collection.RepairSplitMembership();

    public SplitJoin JoinSplit(Guid source, Guid target, int? index, IIdSource ids, DateTimeOffset now) { EnsureAccessible(); return collection.JoinSplit(source, target, index, ids, now); }

    public void LeaveSplit(Guid id, DateTimeOffset now) { EnsureAccessible(); collection.LeaveSplit(id, now); }

    #endregion

    #region Actions - Folders

    public void AddFolder(Guid id, string name, TabPlacement location = TabPlacement.Saved, Guid? parent = null) { EnsureAccessible(); collection.AddFolder(id, name, location, parent); }

    public void RenameFolder(Guid id, string name) { EnsureAccessible(); collection.RenameFolder(id, name); }

    public void CollapseFolder(Guid id, bool collapsed, DateTimeOffset now) { EnsureAccessible(); collection.CollapseFolder(id, collapsed, now); }

    public void DeleteFolder(Guid id, DateTimeOffset now) { EnsureAccessible(); collection.DeleteFolder(id, now); }

    public void FileTabs(IReadOnlyCollection<Guid> requested, TabPlacement location, Guid? folder,
        DateTimeOffset now, Guid? before = null, Guid? beforeFolder = null, bool detachSplitMembers = false) { EnsureAccessible(); collection.FileTabs(requested, location, folder, now, before, beforeFolder, detachSplitMembers); }

    public void MoveFolder(Guid id, TabPlacement? location, Guid? parent, DateTimeOffset now,
        Guid? beforeFolder = null, Guid? beforeTab = null) { EnsureAccessible(); collection.MoveFolder(id, location, parent, now, beforeFolder, beforeTab); }

    #endregion

    #region Actions - Tabs

    public BrowserTab DuplicateTab(Guid id, IIdSource ids, DateTimeOffset now) { EnsureAccessible(); return collection.DuplicateTab(id, ids, now); }

    #endregion

    #region Mutators

    public IReadOnlyList<BrowserTab> SplitMembers(Guid id) => collection.SplitMembers(id);

    #endregion
}
