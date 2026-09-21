namespace CrestCore.Domain;

public sealed record BatchItem(Guid Id, bool IsFolder);
public sealed record BatchTab(TabId Id, TabPlacement Placement, FolderId? FolderId, Guid? SplitGroupId);
public sealed record BatchFolder(FolderId Id, FolderId? ParentId, TabPlacement Location);
public sealed record TabBatchSelection(IReadOnlyList<BatchItem> Roots, IReadOnlyList<BatchTab> Tabs,
    IReadOnlyList<BatchFolder> Folders) {
    public void Validate(BrowserTabCollection source) {
        void Require(bool valid) { if (!valid) throw new BrowserRuleException("stale_selection"); }
        Require(Roots.Count > 0 && Roots.Distinct().Count() == Roots.Count
            && Tabs.Select(t => t.Id).Distinct().Count() == Tabs.Count);
        var tree = new FolderTree(source.Folders);
        var folders = Roots.Where(r => r.IsFolder).Select(r => new FolderId(r.Id)).ToHashSet();
        var covered = folders.SelectMany(f => tree.Subtree(f).Where(id => id != f)).ToHashSet();
        Require(!folders.Overlaps(covered));
        var allFolders = folders.Union(covered).ToHashSet();
        Require(source.Folders.Where(f => allFolders.Contains(f.Id))
            .Select(f => new BatchFolder(f.Id, f.ParentId, f.Location)).SequenceEqual(Folders));
        List<BatchTab> members = [];
        foreach (var root in Roots) {
            if (root.IsFolder) {
                var subtree = tree.Subtree(new(root.Id));
                members.AddRange(source.Tabs.Where(t => t.FolderId is { } f && subtree.Contains(f)).Select(Member));
            } else {
                var tab = source.Tab(new(root.Id));
                Require(tab.FolderId is not { } f || !allFolders.Contains(f));
                members.Add(Member(tab));
            }
        }
        Require(members.SequenceEqual(Tabs));
        var ids = Tabs.Select(t => t.Id).ToHashSet();
        foreach (var member in Tabs) {
            Require(!source.Tab(member.Id).Content.IsStartPage);
            if (source.SplitMembers(member.Id).Any(t => !ids.Contains(t.Id)))
                throw new BrowserRuleException("incomplete_split");
        }
    }
    private static BatchTab Member(BrowserTab tab) => new(tab.Id, tab.Placement, tab.FolderId, tab.SplitGroupId);
}

public enum TabBatchKind { File, NewFolder, NewFolderAround, MoveToSpace, Split, Close, Delete, Duplicate, KeepLoaded, SeparateSplits }
public sealed record TabBatchAction(TabBatchKind Kind, TabPlacement Placement = TabPlacement.Current,
    FolderId? Folder = null, TabId? Before = null, FolderId? BeforeFolder = null,
    TabId? Target = null, int? Index = null, bool KeepLoaded = false, bool Follow = false);
public sealed record TabBatchResult(TabId? Selection, TabId? DestinationSelection,
    IReadOnlyList<(TabId Source, TabId Copy)> Copies, IReadOnlyList<(Guid Source, Guid Copy)> GroupCopies,
    FolderId? CreatedFolder);

public sealed partial class BrowserTabCollection {
    /// Operates on a detached command candidate. The authority publishes it only
    /// after the complete batch, native projection and storage have succeeded.
    public TabBatchResult ApplyBatch(TabBatchSelection request, TabBatchAction action, TabId? selected,
        TabId? fallback, BrowserTabCollection? destination, TabId? destinationSelection, IIdSource ids, DateTimeOffset now) {
        request.Validate(this);
        var requested = request.Tabs.Select(t => t.Id).ToArray();
        var selectedIds = requested.ToHashSet();
        var members = requested.Select(Tab).ToArray();
        var groups = members.Where(t => t.SplitGroupId is not null).Select(t => t.SplitGroupId!.Value).ToHashSet();
        List<(TabId Source, TabId Copy)> copies = [];
        List<(Guid Source, Guid Copy)> groupCopies = [];
        FolderId? createdFolder = null;
        void Require(bool valid, string code = "invalid_destination") { if (!valid) throw new BrowserRuleException(code); }
        FolderId CreateFolder(TabPlacement placement) {
            var folder = new FolderId(ids.Next()); AddFolder(folder, "New Folder", placement); createdFolder = folder; return folder;
        }
        if (request.Folders.Count > 0) {
            switch (action.Kind) {
                case TabBatchKind.File: FileBatchRoots(request, action, now); break;
                case TabBatchKind.NewFolder:
                    FileBatchRoots(request, action with { Folder = CreateFolder(action.Placement) }, now); break;
                case TabBatchKind.KeepLoaded:
                    Require(members.All(t => t.Content.IsWebPage), "web_pages_only");
                    foreach (var tab in members) tab.SetResidency(action.KeepLoaded);
                    break;
                default: throw new BrowserRuleException("folder_action_unavailable");
            }
            return new(selected, destinationSelection, copies, groupCopies, createdFolder);
        }
        Require(requested.Length > 0, "stale_selection");
        switch (action.Kind) {
            case TabBatchKind.File:
                Require(action.Before is not { } anchor || !selectedIds.Contains(anchor));
                if (action.Placement == TabPlacement.Pinned) {
                    Require(groups.Count == 0, "cannot_pin_split");
                    Require(tabs.Count(t => t.Placement == TabPlacement.Pinned && !selectedIds.Contains(t.Id)) + members.Length <= 12,
                        "pinned_capacity");
                    Require(action.Folder is null && action.BeforeFolder is null
                        && (action.Before is not { } before || tabs.Any(t => t.Id == before && t.Placement == TabPlacement.Pinned)));
                    foreach (var tab in requested) MoveTab(tab, TabPlacement.Pinned, null, action.Before, false, now);
                } else {
                    OrderBatchMembers(requested);
                    FileTabs(requested, action.Placement, action.Folder, now, action.Before, action.BeforeFolder);
                }
                break;
            case TabBatchKind.NewFolder:
            case TabBatchKind.NewFolderAround:
                var wrapped = requested;
                if (action.Kind == TabBatchKind.NewFolderAround) {
                    Require(action.Target is not null && !selectedIds.Contains(action.Target.Value));
                    var target = Tab(action.Target!.Value);
                    Require(target.Placement == TabPlacement.Current && target.FolderId is null
                        && target.SplitGroupId is null && !target.Content.IsStartPage);
                    wrapped = [target.Id, .. requested];
                }
                OrderBatchMembers(wrapped);
                FileTabs(wrapped, action.Placement, CreateFolder(action.Placement), now);
                break;
            case TabBatchKind.MoveToSpace:
                Require(groups.Count == 0, "cannot_move_split_across_spaces");
                Require(destination is not null && !ReferenceEquals(this, destination));
                Require(destination!.Tabs.Count(t => t.Placement == TabPlacement.Pinned)
                    + members.Count(t => t.Placement == TabPlacement.Pinned) <= 12, "pinned_capacity");
                var follow = selected is { } active && selectedIds.Contains(active) ? active : requested[0];
                foreach (var tab in requested)
                    selected = TransferTo(destination, tab, selected, fallback, null, null, null, false, destinationSelection, now);
                if (action.Follow) { destination.Tab(follow).Activate(now); destinationSelection = follow; }
                break;
            case TabBatchKind.Split:
                var targetId = action.Target ?? requested[0];
                Require(!Tab(targetId).Content.IsStartPage);
                var existing = SplitMembers(targetId).Select(t => t.Id).ToHashSet();
                Require(existing.Union(selectedIds).Count() is >= 2 and <= MaximumSplitMembers, "split_capacity");
                var insertion = action.Index;
                foreach (var id in requested.Where(id => !existing.Contains(id))) {
                    var oldGroup = Tab(targetId).SplitGroupId;
                    var joined = JoinSplit(id, targetId, insertion, ids, now);
                    copies.AddRange(joined.Copies); selected = joined.SelectedTab;
                    var targetCopy = joined.Copies.FirstOrDefault(p => p.Source == targetId);
                    if (targetCopy != default) {
                        targetId = targetCopy.Copy;
                        if (oldGroup is { } old) groupCopies.Add((old, Tab(targetId).SplitGroupId!.Value));
                    }
                    if (insertion is { } slot) insertion = checked(slot + 1);
                }
                break;
            case TabBatchKind.Close:
            case TabBatchKind.Delete:
                bool deleting = action.Kind == TabBatchKind.Delete;
                Require(deleting || members.All(t => t.Placement == TabPlacement.Current), "current_tabs_only");
                var previous = selected;
                selected = DismissTabs(requested, selected, fallback, now, deleting, deleting, deleting);
                if (deleting && previous is { } removed && selectedIds.Contains(removed))
                    selected = fallback is { } next && tabs.Any(t => t.Id == next) ? next : null;
                break;
            case TabBatchKind.Duplicate:
                foreach (var tab in members)
                    copies.Add((tab.Id, DuplicateTab(tab.Id, ids, now, requestedIndex: tabs.Count).Id));
                foreach (var group in groups) {
                    var copied = members.Where(t => t.SplitGroupId == group)
                        .Select(t => copies.Single(p => p.Source == t.Id).Copy).ToArray();
                    if (copied.Length < 2) continue;
                    var newGroup = ids.Next();
                    foreach (var tab in copied.Skip(1)) JoinSplitInPlace(tab, copied[0], null, newGroup, now);
                    groupCopies.Add((group, newGroup));
                }
                break;
            case TabBatchKind.KeepLoaded:
                Require(members.All(t => t.Content.IsWebPage), "web_pages_only");
                foreach (var tab in members) tab.SetResidency(action.KeepLoaded);
                break;
            case TabBatchKind.SeparateSplits:
                foreach (var group in groups) DissolveSplit(group, now);
                break;
        }
        return new(selected, destinationSelection, copies, groupCopies, createdFolder);
    }

    private void OrderBatchMembers(IReadOnlyList<TabId> requested) {
        var members = requested.Select(Tab).ToArray(); var ids = requested.ToHashSet();
        int insertion = tabs.FindIndex(t => ids.Contains(t.Id));
        tabs.RemoveAll(t => ids.Contains(t.Id)); tabs.InsertRange(insertion, members);
    }

    private void FileBatchRoots(TabBatchSelection request, TabBatchAction action, DateTimeOffset now) {
        var folderIds = request.Folders.Select(f => f.Id).ToHashSet();
        var tabIds = request.Tabs.Select(t => t.Id).ToHashSet();
        if (action.Placement == TabPlacement.Pinned || action.Folder is { } parent && folderIds.Contains(parent)
            || action.Before is { } before && tabIds.Contains(before)
            || action.BeforeFolder is { } beforeFolder && folderIds.Contains(beforeFolder))
            throw new BrowserRuleException("invalid_destination");
        var tree = new FolderTree(folders);
        if (action.Folder is { } owner && tree.Folder(owner).Location != action.Placement
            || action.BeforeFolder is { } sibling && (tree.Folder(sibling).ParentId != action.Folder
                || tree.Folder(sibling).Location != action.Placement)
            || action.BeforeFolder is null && action.Before is { } anchor && (Tab(anchor).FolderId != action.Folder
                || Tab(anchor).Placement != action.Placement || SplitMembers(anchor)[0].Id != anchor))
            throw new BrowserRuleException("invalid_destination");
        List<(BatchItem Item, TabId[] Tabs)> blocks = []; HashSet<TabId> included = [];
        foreach (var root in request.Roots) {
            if (root.IsFolder) blocks.Add((root, []));
            else if (!included.Contains(new(root.Id))) {
                var members = SplitMembers(new(root.Id)).Select(t => t.Id).ToArray();
                included.UnionWith(members); blocks.Add((root, members));
            }
        }
        var tabAnchor = action.Before; var folderAnchor = action.BeforeFolder;
        foreach (var block in blocks.AsEnumerable().Reverse()) {
            if (block.Item.IsFolder) {
                var folder = new FolderId(block.Item.Id);
                MoveFolder(folder, action.Placement, action.Folder, now, folderAnchor, tabAnchor);
                folderAnchor = folder; tabAnchor = null;
            } else {
                FileTabs(block.Tabs, action.Placement, action.Folder, now, tabAnchor, folderAnchor);
                tabAnchor = block.Tabs[0]; folderAnchor = null;
            }
        }
    }
}
