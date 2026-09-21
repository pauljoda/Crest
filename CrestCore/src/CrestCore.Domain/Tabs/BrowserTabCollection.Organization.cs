namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    public void AddFolder(FolderId id, string name, TabPlacement location = TabPlacement.Saved, FolderId? parent = null) {
        var tree = new FolderTree(folders);
        if (folders.Count >= FolderTree.MaximumCount) throw new BrowserRuleException("folder_limit");
        if (folders.Any(f => f.Id == id)) throw new BrowserRuleException("duplicate_folder");
        if (location == TabPlacement.Pinned) throw new BrowserRuleException("invalid_folder_placement");
        int insertion = folders.Count;
        if (parent is { } p) {
            if (tree.Depth(p) + 1 >= FolderTree.MaximumDepth) throw new BrowserRuleException("folder_depth_limit");
            location = tree.Folder(p).Location;
            var subtree = tree.Subtree(p); insertion = folders.FindLastIndex(f => subtree.Contains(f.Id)) + 1;
        }
        folders.Insert(insertion, new(id, FolderName(name), location, parent));
    }
    private static string FolderName(string name) => string.IsNullOrWhiteSpace(name) ? "Untitled Folder" : BrowserSpace.ValidName(name);
    public void RenameFolder(FolderId id, string name) {
        var folder = new FolderTree(folders).Folder(id);
        folders[folders.IndexOf(folder)] = folder with { Name = FolderName(name) };
    }
    public void CollapseFolder(FolderId id, bool collapsed, DateTimeOffset now) {
        var folder = new FolderTree(folders).Folder(id);
        if (folder.IsCollapsed == collapsed) return;
        folders[folders.IndexOf(folder)] = folder with { IsCollapsed = collapsed, CollapseModifiedAt = now };
    }
    public void DeleteFolder(FolderId id, DateTimeOffset now) {
        var folder = new FolderTree(folders).Folder(id);
        var next = folders.Where(f => f.Id != id).Select(f => f.ParentId == id ? f with { ParentId = folder.ParentId } : f).ToArray();
        var ordered = new FolderTree(next).DisplayOrder();
        foreach (var tab in tabs.Where(t => t.FolderId == id))
            tab.Place(tab.Placement, folder.ParentId, now, preservesSplit: true);
        folders.Clear(); folders.AddRange(ordered);
    }
    private static void ValidateInsertion(IReadOnlyList<BrowserTab> remaining, int insertion) {
        if (insertion > 0 && insertion < remaining.Count && remaining[insertion].SplitGroupId is { } split
            && remaining[insertion - 1].SplitGroupId == split) throw new BrowserRuleException("split_boundary");
    }
    private static int SectionEnd(List<BrowserTab> remaining, TabPlacement location) {
        int last = remaining.FindLastIndex(t => t.Placement == location);
        if (last >= 0) return last + 1;
        int current = remaining.FindIndex(t => t.Placement == TabPlacement.Current);
        return location == TabPlacement.Saved && current >= 0 ? current : remaining.Count;
    }
    internal void NormalizeSplits(DateTimeOffset now) {
        RepairSplitMembership();
        foreach (var group in tabs.Where(t => t.SplitGroupId is not null).GroupBy(t => t.SplitGroupId))
            if (group.Count() < 2) foreach (var tab in group) { tab.SetSplit(null); tab.MarkPosition(now); }
    }
    public void FileTabs(IReadOnlyCollection<TabId> requested, TabPlacement location, FolderId? folder,
        DateTimeOffset now, TabId? before = null, FolderId? beforeFolder = null, bool detachSplitMembers = false) {
        if (requested.Count == 0 || location == TabPlacement.Pinned) throw new BrowserRuleException("invalid_folder_placement");
        foreach (var id in requested) _ = Tab(id);
        var tree = new FolderTree(folders);
        if (folder is { } parent && tree.Folder(parent).Location != location) throw new BrowserRuleException("invalid_folder_placement");
        if (beforeFolder is { } sibling && (tree.Folder(sibling).ParentId != folder || tree.Folder(sibling).Location != location))
            throw new BrowserRuleException("invalid_folder_anchor");
        var selected = requested.ToHashSet();
        var splits = detachSplitMembers ? [] : tabs.Where(t => selected.Contains(t.Id) && t.SplitGroupId is not null)
            .Select(t => t.SplitGroupId!.Value).ToHashSet();
        var members = tabs.Where(t => selected.Contains(t.Id) || t.SplitGroupId is { } s && splits.Contains(s)).ToArray();
        var memberIds = members.Select(t => t.Id).ToHashSet();
        var remaining = tabs.Where(t => !memberIds.Contains(t.Id)).ToList();
        var nextFolders = tree.PreserveOrder(memberIds, tabs);
        var remainingTree = new FolderTree(nextFolders);
        var anchor = beforeFolder is { } target ? remainingTree.TabAnchor(target, remaining) : before;
        if (anchor is { } a && (memberIds.Contains(a) || !remaining.Any(t => t.Id == a && t.Placement == location)))
            throw new BrowserRuleException("invalid_tab_anchor");
        var predecessors = remainingTree.EmptyPredecessors(beforeFolder, anchor, folder, location, remaining);
        int insertion;
        if (anchor is { } actual) insertion = remaining.FindIndex(t => t.Id == actual);
        else if (folder is not null && remaining.FindLastIndex(t => t.FolderId == folder) is var last && last >= 0) insertion = last + 1;
        else insertion = folder is null ? SectionEnd(remaining, location) : Math.Min(tabs.FindIndex(t => memberIds.Contains(t.Id)), remaining.Count);
        if (detachSplitMembers && anchor is null && insertion > 0 && insertion < remaining.Count
            && remaining[insertion].SplitGroupId is { } crossing && remaining[insertion - 1].SplitGroupId == crossing)
            while (insertion < remaining.Count && remaining[insertion].SplitGroupId == crossing) insertion++;
        ValidateInsertion(remaining, insertion);
        nextFolders = nextFolders.Select(f => predecessors.Contains(f.Id) ? f with { OrderAnchorTabId = members[0].Id } : f).ToList();
        // No mutation before all topology and split-boundary checks have passed.
        foreach (var tab in members) {
            tab.Place(location, folder, now, preservesSplit: !detachSplitMembers);
            if (detachSplitMembers) tab.SetSplit(null);
            tab.MarkPosition(now);
        }
        remaining.InsertRange(insertion, members);
        tabs.Clear(); tabs.AddRange(remaining); folders.Clear(); folders.AddRange(nextFolders);
        if (detachSplitMembers) NormalizeSplits(now);
    }
    public void MoveFolder(FolderId id, TabPlacement? location, FolderId? parent, DateTimeOffset now,
        FolderId? beforeFolder = null, TabId? beforeTab = null) {
        var tree = new FolderTree(folders); var source = tree.Folder(id);
        var movingIds = tree.Subtree(id);
        if (parent is { } p && movingIds.Contains(p)) throw new BrowserRuleException("folder_cycle");
        int destinationDepth = parent is { } parentId ? tree.Depth(parentId) + 1 : 0;
        if (destinationDepth + movingIds.Max(tree.Depth) - tree.Depth(id) >= FolderTree.MaximumDepth)
            throw new BrowserRuleException("folder_depth_limit");
        var destination = parent is { } owner ? tree.Folder(owner).Location : location ?? source.Location;
        if (destination == TabPlacement.Pinned) throw new BrowserRuleException("invalid_folder_placement");
        if (beforeFolder is { } sibling && (movingIds.Contains(sibling) || tree.Folder(sibling).ParentId != parent
            || tree.Folder(sibling).Location != destination)) throw new BrowserRuleException("invalid_folder_anchor");
        var members = tabs.Where(t => t.FolderId is { } f && movingIds.Contains(f)).ToArray();
        var memberIds = members.Select(t => t.Id).ToHashSet();
        if (beforeTab is { } a && (memberIds.Contains(a) || !tabs.Any(t => t.Id == a && t.Placement == destination)))
            throw new BrowserRuleException("invalid_tab_anchor");
        var nextFolders = tree.PreserveOrder(memberIds, tabs, movingIds);
        var remaining = tabs.Where(t => !memberIds.Contains(t.Id)).ToList();
        var remainingTree = new FolderTree(nextFolders);
        var anchor = beforeFolder is { } target ? remainingTree.TabAnchor(target, remaining) : beforeTab;
        var predecessors = remainingTree.EmptyPredecessors(beforeFolder, anchor, parent, destination, remaining);
        var moving = nextFolders.Where(f => movingIds.Contains(f.Id)).Select(f => f with { Location = destination, ParentId = f.Id == id ? parent : f.ParentId, OrderAnchorTabId = f.Id == id ? anchor : f.OrderAnchorTabId }).ToArray();
        nextFolders.RemoveAll(f => movingIds.Contains(f.Id));
        int folderInsertion = beforeFolder is { } bf ? nextFolders.FindIndex(f => f.Id == bf)
            : parent is { } parentFolder ? nextFolders.FindLastIndex(f => tree.Subtree(parentFolder).Contains(f.Id)) + 1 : nextFolders.Count;
        nextFolders.InsertRange(folderInsertion, moving);
        nextFolders = new FolderTree(nextFolders).DisplayOrder().ToList();
        int insertion;
        if (anchor is { } actual && remaining.FindIndex(t => t.Id == actual) is var at && at >= 0) insertion = at;
        else if (parent is { } targetParent && remaining.FindLastIndex(t => t.FolderId is { } f && tree.Subtree(targetParent).Contains(f)) is var last && last >= 0)
            insertion = last + 1;
        else insertion = SectionEnd(remaining, destination);
        ValidateInsertion(remaining, insertion);
        foreach (var tab in members) { tab.Place(destination, tab.FolderId, now, preservesSplit: true); tab.MarkPosition(now); }
        remaining.InsertRange(insertion, members);
        if (members.Length > 0) nextFolders = nextFolders.Select(f => predecessors.Contains(f.Id) && !movingIds.Contains(f.Id)
            ? f with { OrderAnchorTabId = members[0].Id } : f).ToList();
        tabs.Clear(); tabs.AddRange(remaining); folders.Clear(); folders.AddRange(nextFolders);
    }
}
