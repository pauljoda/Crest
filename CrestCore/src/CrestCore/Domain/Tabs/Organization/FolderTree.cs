using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The same bounded forest and stable tab-boundary ordering used by Crest's native sidebars.
/// A tree reads its folders as they stand when it is made.
public sealed class FolderTree(IReadOnlyList<FolderState> folders) {
    #region Static Variables

    public const int MaximumDepth = FolderState.MaximumDepth;
    public const int MaximumCount = 500;

    #endregion

    #region Variables

    /// Each folder by its identity, the first of any that share one, so a
    /// lookup never searches the list.
    private readonly Dictionary<Guid, FolderState> byId = Index(folders);

    #endregion

    #region Actions - Organization

    private static Dictionary<Guid, FolderState> Index(IReadOnlyList<FolderState> folders) {
        ArgumentNullException.ThrowIfNull(folders);
        var index = new Dictionary<Guid, FolderState>(folders.Count);
        foreach (var folder in folders) index.TryAdd(folder.Id, folder);
        return index;
    }

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
            throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
        foreach (var folder in folders) {
            if (!folder.Location.HoldsFolders || folder.ParentId is { } parent && Folder(parent).Location != folder.Location)
                throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
            _ = Depth(folder.Id);
        }
    }

    public IReadOnlyList<FolderState> DisplayOrder() {
        Validate(); List<FolderState> result = [];
        void Append(Guid? parent) {
            foreach (var folder in Children(parent)) { result.Add(folder); Append(folder.Id); }
        }
        Append(null); return [.. result];
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

    public FolderState Folder(Guid id) => byId.TryGetValue(id, out var folder) ? folder
        : throw new BrowserRuleException(BrowserRule.UnknownFolder);

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
            if (!seen.Add(parent) || ++depth >= MaximumDepth) throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
            folder = Folder(parent);
        }
        return depth;
    }

    /// The titles from the outermost folder down to `id`, joined as a path, as
    /// the palette names where a saved tab lives.
    public string PathTitle(Guid id) {
        var folder = Folder(id);
        List<string> titles = [folder.Title];
        HashSet<Guid> seen = [id];
        while (folder.ParentId is { } parent && seen.Add(parent)) {
            folder = Folder(parent);
            titles.Add(folder.Title);
        }
        titles.Reverse();
        return string.Join(" › ", titles);
    }

    public Guid? TabAnchor(Guid id, IReadOnlyList<BrowserTab> tabs) {
        var subtree = Subtree(id);
        return tabs.FirstOrDefault(tab => tab.FolderId is { } folderId && subtree.Contains(folderId))?.Id
            ?? (Folder(id).OrderAnchorTabId is { } anchor && tabs.Any(tab => tab.Id == anchor) ? anchor : null);
    }

    #endregion
}
