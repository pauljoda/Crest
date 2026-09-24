using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// What a folder created without a title is called.
    private const string NewFolderTitle = "New Folder";

    #endregion

    #region Actions - Folders

    /// Creates the folder and files its tabs in one edit.
    private SessionEdit CreatingFolder(SessionState basis, CreateFolder intent, DateTimeOffset now) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Creation, edited => {
            edited.AddFolder(intent.FolderId, string.IsNullOrWhiteSpace(intent.Title) ? NewFolderTitle : intent.Title,
                intent.Placement, intent.ParentId);
            if (intent.Color is { } color) edited.SetFolderColor(intent.FolderId, color);
            if (intent.Symbol is { } symbol) edited.SetFolderSymbol(intent.FolderId, symbol);
            if (intent.TabIds.Count > 0)
                edited.FileTabs(intent.TabIds, intent.Placement, intent.FolderId, now, null, null, intent.LeavesSplits);
        });

    private SessionEdit RenamingFolder(SessionState basis, RenameFolder intent) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => edited.RenameFolder(intent.FolderId, intent.Title));

    private SessionEdit CollapsingFolder(SessionState basis, CollapseFolder intent, DateTimeOffset now) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => edited.CollapseFolder(intent.FolderId, intent.Collapsed, now));

    private SessionEdit ColoringFolder(SessionState basis, SetFolderColor intent) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => edited.SetFolderColor(intent.FolderId, intent.Color));

    private SessionEdit SymbolizingFolder(SessionState basis, SetFolderSymbol intent) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => edited.SetFolderSymbol(intent.FolderId, intent.Symbol));

    private SessionEdit MovingFolder(SessionState basis, MoveFolder intent, DateTimeOffset now) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited =>
            edited.MoveFolder(intent.FolderId, intent.Placement, intent.ParentId, now, intent.BeforeFolderId, intent.BeforeTabId));

    private SessionEdit DeletingFolder(SessionState basis, DeleteFolder intent, DateTimeOffset now) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Deletion, edited => edited.DeleteFolder(intent.FolderId, now));

    /// Files the selection, saved with its journal before the intent returns
    /// as every action on a selection is. Tabs taken out of their splits
    /// leave split metadata no tab uses, which goes with them.
    private SessionEdit Filing(SessionState basis, FileTabs intent, DateTimeOffset now) {
        var batch = Selecting(basis, intent.WindowId, intent.SpaceId, intent.Selection);
        batch.Edited.FileSelected(batch.Selected, intent.Placement, intent.FolderId, intent.BeforeTabId, intent.BeforeFolderId,
            intent.LeavesSplits, now);
        return batch.Result(basis, SyncStaging.Batch);
    }

    #endregion

    #region Actions - Splits

    private SessionEdit JoiningSplit(SessionState basis, JoinSplit intent, DateTimeOffset now, IIdSource ids, Pages? pages) {
        var space = Editable(basis, intent.SpaceId);
        return Joining(basis, space, BrowserTabCollection.Restore(space), intent.WindowId, intent.TabId, intent.TargetTabId,
            intent.Index, pages, now, ids);
    }

    /// Opens the link as a new open tab and joins it to the target's split.
    private SessionEdit OpeningLinkInSplit(SessionState basis, OpenLinkInSplit intent, DateTimeOffset now, IIdSource ids,
        Pages? pages) {
        var space = Editable(basis, intent.SpaceId);
        if (basis.Spaces.Any(candidate => candidate.Tabs.Any(tab => tab.Id == intent.TabId)))
            throw new Rejected(new TabAlreadyExists(intent.TabId));
        var edited = BrowserTabCollection.Restore(space);
        edited.InsertTab(BrowserTab.Restore(new TabState(intent.TabId, intent.Title, intent.Address, NativeContent: null,
            SavedUrl: null, TabIconMode.WebSymbol, FaviconUrl: null, IconAccent: null, StoredIconMode: null, TabPlacement.Current,
            FolderId: null, SplitGroupId: null, now, PositionModifiedAt: null, CustomTitle: null, TitleModifiedAt: null,
            KeepsPageLoaded: false)), null);
        return Joining(basis, space, edited, intent.WindowId, intent.TabId, intent.TargetTabId, null, pages, now, ids);
    }

    /// Joins `tabId` to the split of `targetId` in `edited`, the organization
    /// of `space`, and shows the joined tab in the issuing window. A copy
    /// starts from where its source's page is now; see `StartFromSourcePage`.
    /// A durable target's split copied into new tabs keeps its name, icon and
    /// tint.
    private SessionEdit Joining(SessionState basis, SpaceState space, BrowserTabCollection edited, Guid windowId, Guid tabId, Guid targetId,
        int? index, Pages? pages, DateTimeOffset now, IIdSource ids) {
        var target = edited.Tab(targetId);
        var durableGroup = target.Placement.IsDurable ? target.SplitGroupId : null;
        var joined = edited.JoinSplit(tabId, targetId, index, ids, now);
        foreach (var (source, copyId) in joined.Copies) StartFromSourcePage(edited.Tab(copyId), source, windowId, pages);
        if (durableGroup is { } copied && joined.Copies.Any(pair => pair.Source == targetId)
            && edited.Tab(joined.SelectedTab).SplitGroupId is { } copy)
            edited.CopySplitMetadata(copied, copy, now);
        edited.PruneSplitMetadata();
        var followUp = new WindowFollowUp(IssuingWindow(windowId)).ShowTab(space.Id, joined.SelectedTab).ShowSpace(space.Id);
        return new(Replacing(basis, edited.Capture(space)), SyncStaging.Edit, followUp,
            new([.. joined.Copies.Select(pair => new SessionTabCopy(pair.Source, pair.Copy))], null));
    }

    private SessionEdit LeavingSplit(SessionState basis, LeaveSplit intent, DateTimeOffset now) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => {
            edited.LeaveSplit(intent.TabId, now);
            edited.PruneSplitMetadata();
        });

    private SessionEdit MovingSplitMember(SessionState basis, MoveSplitMember intent, DateTimeOffset now) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => edited.MoveSplitMember(intent.TabId, intent.Index, now));

    private SessionEdit SteppingSplitMember(SessionState basis, StepSplitMember intent, DateTimeOffset now) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => edited.StepSplitMember(intent.TabId, intent.Offset, now));

    private SessionEdit DissolvingSplit(SessionState basis, DissolveSplit intent, DateTimeOffset now) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited => {
            edited.DissolveSplit(intent.GroupId, now);
            edited.PruneSplitMetadata();
        });

    private SessionEdit MovingSplit(SessionState basis, MoveSplit intent, DateTimeOffset now) =>
        Organizing(basis, intent.SpaceId, SyncStaging.Edit, edited =>
            edited.MoveSplitGroup(intent.GroupId, intent.Placement, intent.FolderId, intent.BeforeTabId, now));

    /// `space`'s organization after `edit`, with the Space's other records kept.
    private SessionEdit Organizing(SessionState basis, Guid spaceId, SyncStaging staging, Action<BrowserTabCollection> edit) {
        var space = Editable(basis, spaceId);
        var edited = BrowserTabCollection.Restore(space);
        edit(edited);
        return new(Replacing(basis, edited.Capture(space)), staging);
    }

    #endregion

    #region Actions - Split identity

    /// A blank name clears it; a name is kept trimmed.
    private SessionEdit NamingSplit(SessionState basis, NameSplit intent, DateTimeOffset now) =>
        Identifying(basis, intent.SpaceId, intent.GroupId, now, group =>
            group with { CustomTitle = string.IsNullOrWhiteSpace(intent.Name) ? null : intent.Name.Trim() },
            (group, changedAt) => group with { TitleModifiedAt = changedAt });

    private SessionEdit SettingSplitIcon(SessionState basis, SetSplitIcon intent, DateTimeOffset now) =>
        Identifying(basis, intent.SpaceId, intent.GroupId, now, group => group with { CustomIconSymbol = intent.Symbol },
            (group, changedAt) => group with { IconModifiedAt = changedAt });

    private SessionEdit TintingSplit(SessionState basis, TintSplit intent, DateTimeOffset now) =>
        Identifying(basis, intent.SpaceId, intent.GroupId, now, group => group with { Tint = intent.Tint },
            (group, changedAt) => group with { TintModifiedAt = changedAt });

    /// A split's name, icon or tint, which only a split of two or more tabs
    /// has. `choose` sets the field; `stamp` records when, so each field merges
    /// on its own. A choice that is already the split's changes nothing.
    private SessionEdit Identifying(SessionState basis, Guid spaceId, Guid groupId, DateTimeOffset now,
        Func<SplitGroupState, SplitGroupState> choose, Func<SplitGroupState, DateTimeOffset, SplitGroupState> stamp) {
        var space = Editable(basis, spaceId);
        var run = space.Tabs.SkipWhile(tab => tab.SplitGroupId != groupId).TakeWhile(tab => tab.SplitGroupId == groupId);
        if (run.Take(2).Count() < 2) throw new Rejected(new UnknownSplitGroup(groupId));
        var existing = space.SplitGroups.FirstOrDefault(group => group.Id == groupId);
        var current = existing ?? new SplitGroupState(groupId);
        var chosen = choose(current);
        if (chosen == current) return new(basis, SyncStaging.Edit);
        var edited = stamp(chosen, BrowserEditTimestamp.Normalize(now));
        IReadOnlyList<SplitGroupState> groups = existing is null ? [.. space.SplitGroups, edited]
            : [.. space.SplitGroups.Select(candidate => candidate.Id == groupId ? edited : candidate)];
        return new(Replacing(basis, space with { SplitGroups = groups }), SyncStaging.Edit);
    }

    #endregion
}
