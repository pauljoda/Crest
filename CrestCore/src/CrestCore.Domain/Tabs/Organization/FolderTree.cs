using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The same bounded forest and stable tab-boundary ordering used by Crest's native sidebars.
public sealed class FolderTree(IReadOnlyList<FolderState> folders) {
    #region Variables

    public const int MaximumDepth = FolderState.MaximumDepth;
    public const int MaximumCount = 500;

    #endregion

    #region Actions - Organization

    public static IReadOnlyList<FolderState> RepairPreorder(IReadOnlyList<FolderState> source) {
        List<FolderState> accepted = [];
        Dictionary<Guid, (int Depth, TabPlacement Location)> parents = [];
        foreach (var folder in source.Take(MaximumCount)) {
            var parent = folder.ParentId;
            if (parent is not { } requested || requested == folder.Id || !parents.TryGetValue(requested, out var found)
                || found.Depth + 1 >= MaximumDepth) parent = null;
            var repaired = folder with { ParentId = parent, Location = parent is { } p ? parents[p].Location : folder.Location };
            accepted.Add(repaired);
            parents[folder.Id] = (parent is { } id ? parents[id].Depth + 1 : 0, repaired.Location);
        }
        return new FolderTree(accepted).DisplayOrder();
    }

    public void Validate() {
        if (folders.Count > MaximumCount || folders.Select(f => f.Id).Distinct().Count() != folders.Count)
            throw new BrowserRuleException(BrowserRuleCodes.InvalidFolderTree);
        foreach (var folder in folders) {
            if (!folder.Location.HoldsFolders || folder.ParentId is { } parent && Folder(parent).Location != folder.Location)
                throw new BrowserRuleException(BrowserRuleCodes.InvalidFolderTree);
            _ = Depth(folder.Id);
        }
    }

    public IReadOnlyList<FolderState> DisplayOrder() {
        Validate(); List<FolderState> result = [];
        void Append(Guid? parent) {
            foreach (var folder in Children(parent)) { result.Add(folder); Append(folder.Id); }
        }
        Append(null); return result;
    }

    public HashSet<Guid> EmptyPredecessors(Guid? before, Guid? anchor, Guid? parent,
        TabPlacement placement, IReadOnlyList<BrowserTab> tabs) {
        HashSet<Guid> result = [];
        var target = before is { } id ? Subtree(id) : [];
        bool targetEmpty = !tabs.Any(tab => tab.FolderId is { } folderId && target.Contains(folderId));
        foreach (var folder in Children(parent).Where(f => f.Location == placement)) {
            if (folder.Id == before && targetEmpty) break;
            var subtree = Subtree(folder.Id);
            if (!tabs.Any(tab => tab.FolderId is { } folderId && subtree.Contains(folderId)) && TabAnchor(folder.Id, tabs) == anchor)
                result.Add(folder.Id);
        }
        return result;
    }

    public List<FolderState> PreserveOrder(HashSet<Guid> removed, IReadOnlyList<BrowserTab> tabs,
        HashSet<Guid>? excluding = null) => folders.Select(folder => {
            if (excluding?.Contains(folder.Id) == true) return folder;
            var subtree = Subtree(folder.Id);
            var members = tabs.Where(tab => tab.FolderId is { } folderId && subtree.Contains(folderId)).ToArray();
            if (members.Any(tab => !removed.Contains(tab.Id))) return folder;
            var old = members.FirstOrDefault()?.Id ?? folder.OrderAnchorTabId;
            if (old is not { } anchor || !removed.Contains(anchor)) return folder;
            int start = tabs.ToList().FindIndex(tab => tab.Id == anchor);
            if (start < 0) return folder;
            var parent = folder.ParentId is { } p ? Subtree(p) : null;
            return folder with {
                OrderAnchorTabId = tabs.Skip(start).FirstOrDefault(tab => !removed.Contains(tab.Id)
                && tab.Placement == folder.Location && (parent is null || tab.FolderId is { } folderId && parent.Contains(folderId)))?.Id
            };
        }).ToList();

    #endregion

    #region Mutators

    public FolderState Folder(Guid id) => folders.FirstOrDefault(f => f.Id == id)
        ?? throw new BrowserRuleException(BrowserRuleCodes.UnknownFolder);

    public IEnumerable<FolderState> Children(Guid? id) => folders.Where(f => f.ParentId == id);

    public HashSet<Guid> Subtree(Guid id) {
        _ = Folder(id);
        HashSet<Guid> result = []; Stack<Guid> pending = new([id]);
        while (pending.TryPop(out var next))
            if (result.Add(next)) foreach (var child in Children(next)) pending.Push(child.Id);
        return result;
    }

    public int Depth(Guid id) {
        var folder = Folder(id); var depth = 0; HashSet<Guid> seen = [id];
        while (folder.ParentId is { } parent) {
            if (!seen.Add(parent) || ++depth >= MaximumDepth) throw new BrowserRuleException(BrowserRuleCodes.InvalidFolderTree);
            folder = Folder(parent);
        }
        return depth;
    }

    public Guid? TabAnchor(Guid id, IReadOnlyList<BrowserTab> tabs) {
        var subtree = Subtree(id);
        return tabs.FirstOrDefault(tab => tab.FolderId is { } folderId && subtree.Contains(folderId))?.Id
            ?? (Folder(id).OrderAnchorTabId is { } anchor && tabs.Any(tab => tab.Id == anchor) ? anchor : null);
    }

    #endregion
}
