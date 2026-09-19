namespace CrestCore.Domain;

/// The same bounded forest and stable tab-boundary ordering used by Crest's native sidebars.
public sealed class FolderTree(IReadOnlyList<BrowserFolder> folders)
{
    public const int MaximumDepth = 16;
    public const int MaximumCount = 500;
    public BrowserFolder Folder(FolderId id) => folders.FirstOrDefault(f => f.Id == id)
        ?? throw new BrowserRuleException("unknown_folder");
    public IEnumerable<BrowserFolder> Children(FolderId? id) => folders.Where(f => f.ParentId == id);
    public HashSet<FolderId> Subtree(FolderId id)
    {
        _ = Folder(id);
        HashSet<FolderId> result = []; Stack<FolderId> pending = new([id]);
        while (pending.TryPop(out var next))
            if (result.Add(next)) foreach (var child in Children(next)) pending.Push(child.Id);
        return result;
    }
    public int Depth(FolderId id)
    {
        var folder = Folder(id); var depth = 0; HashSet<FolderId> seen = [id];
        while (folder.ParentId is { } parent)
        {
            if (!seen.Add(parent) || ++depth >= MaximumDepth) throw new BrowserRuleException("invalid_folder_tree");
            folder = Folder(parent);
        }
        return depth;
    }
    public void Validate()
    {
        if (folders.Count > MaximumCount || folders.Select(f => f.Id).Distinct().Count() != folders.Count)
            throw new BrowserRuleException("invalid_folder_tree");
        foreach (var folder in folders)
        {
            if (folder.Location == TabPlacement.Pinned || folder.ParentId is { } parent && Folder(parent).Location != folder.Location)
                throw new BrowserRuleException("invalid_folder_tree");
            _ = Depth(folder.Id);
        }
    }
    public IReadOnlyList<BrowserFolder> DisplayOrder()
    {
        Validate(); List<BrowserFolder> result = [];
        void Append(FolderId? parent)
        {
            foreach (var folder in Children(parent)) { result.Add(folder); Append(folder.Id); }
        }
        Append(null); return result;
    }
    public TabId? TabAnchor(FolderId id, IReadOnlyList<BrowserTab> tabs)
    {
        var subtree = Subtree(id);
        return tabs.FirstOrDefault(t => t.FolderId is { } f && subtree.Contains(f))?.Id
            ?? (Folder(id).OrderAnchorTabId is { } anchor && tabs.Any(t => t.Id == anchor) ? anchor : null);
    }
    public HashSet<FolderId> EmptyPredecessors(FolderId? before, TabId? anchor, FolderId? parent,
        TabPlacement placement, IReadOnlyList<BrowserTab> tabs)
    {
        HashSet<FolderId> result = [];
        var target = before is { } id ? Subtree(id) : [];
        bool targetEmpty = !tabs.Any(t => t.FolderId is { } f && target.Contains(f));
        foreach (var folder in Children(parent).Where(f => f.Location == placement))
        {
            if (folder.Id == before && targetEmpty) break;
            var subtree = Subtree(folder.Id);
            if (!tabs.Any(t => t.FolderId is { } f && subtree.Contains(f)) && TabAnchor(folder.Id, tabs) == anchor)
                result.Add(folder.Id);
        }
        return result;
    }
    public List<BrowserFolder> PreserveOrder(HashSet<TabId> removed, IReadOnlyList<BrowserTab> tabs,
        HashSet<FolderId>? excluding = null) => folders.Select(folder =>
    {
        if (excluding?.Contains(folder.Id) == true) return folder;
        var subtree = Subtree(folder.Id);
        var members = tabs.Where(t => t.FolderId is { } f && subtree.Contains(f)).ToArray();
        if (members.Any(t => !removed.Contains(t.Id))) return folder;
        var old = members.FirstOrDefault()?.Id ?? folder.OrderAnchorTabId;
        if (old is not { } anchor || !removed.Contains(anchor)) return folder;
        int start = tabs.ToList().FindIndex(t => t.Id == anchor);
        if (start < 0) return folder;
        var parent = folder.ParentId is { } p ? Subtree(p) : null;
        return folder with { OrderAnchorTabId = tabs.Skip(start).FirstOrDefault(t => !removed.Contains(t.Id)
            && t.Placement == folder.Location && (parent is null || t.FolderId is { } f && parent.Contains(f)))?.Id };
    }).ToList();
}
