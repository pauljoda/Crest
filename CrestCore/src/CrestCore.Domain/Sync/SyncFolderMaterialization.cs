using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Resolves partial deliveries without confusing an unknown parent with a
/// deleted one. The caller supplies stable sibling order from the sync records.
public static class SyncFolderMaterialization {
    #region Actions - Sync

    public static bool TryPromote(Guid missing, HashSet<Guid> active,
        IReadOnlyDictionary<Guid, FolderState> local, HashSet<Guid> deleted,
        out Guid? parent) {
        parent = missing;
        HashSet<Guid> seen = [];
        while (parent is { } candidate) {
            if (active.Contains(candidate)) return true;
            if (!deleted.Contains(candidate) || !seen.Add(candidate) || !local.TryGetValue(candidate, out var folder)) return false;
            parent = folder.ParentId;
        }
        return true;
    }

    public static IReadOnlyList<FolderState> Resolve(Guid space, IReadOnlyList<FolderState> ordered,
        IReadOnlyDictionary<Guid, Guid> owners, IReadOnlyDictionary<Guid, FolderState> local,
        HashSet<Guid> deleted) {
        if (ordered.Count > FolderTree.MaximumCount || ordered.Select(f => f.Id).Distinct().Count() != ordered.Count)
            throw new BrowserRuleException(BrowserRuleCodes.InvalidFolderTree);
        var active = ordered.Select(f => f.Id).ToHashSet();
        List<FolderState> roots = [];
        Dictionary<Guid, List<FolderState>> children = [];
        HashSet<Guid> waiting = [];
        foreach (var source in ordered) {
            var folder = source;
            if (folder.ParentId is { } parent) {
                if (parent == folder.Id) throw new BrowserRuleException(BrowserRuleCodes.InvalidFolderTree);
                if (!active.Contains(parent)) {
                    if (owners.TryGetValue(parent, out var owner) && owner != space) throw new BrowserRuleException(BrowserRuleCodes.InvalidFolderTree);
                    if (!TryPromote(parent, active, local, deleted, out var promoted)) { waiting.Add(folder.Id); continue; }
                    folder = folder with { ParentId = promoted };
                }
            }
            if (folder.ParentId is { } resolved) {
                if (!children.TryGetValue(resolved, out var siblings)) children[resolved] = siblings = [];
                siblings.Add(folder);
            } else roots.Add(folder);
        }
        HashSet<Guid> visited = [];
        List<FolderState> result = [];
        void Append(FolderState folder, int depth) {
            if (depth >= FolderTree.MaximumDepth || !visited.Add(folder.Id)) throw new BrowserRuleException(BrowserRuleCodes.InvalidFolderTree);
            result.Add(folder);
            foreach (var child in children.GetValueOrDefault(folder.Id) ?? []) Append(child, depth + 1);
        }
        foreach (var root in roots) Append(root, 0);
        Stack<Guid> pending = new(waiting);
        while (pending.TryPop(out var next))
            foreach (var child in children.GetValueOrDefault(next) ?? []) if (waiting.Add(child.Id)) pending.Push(child.Id);
        if (visited.Count + waiting.Count != ordered.Count) throw new BrowserRuleException(BrowserRuleCodes.InvalidFolderTree);
        new FolderTree(result).Validate();
        return result;
    }

    #endregion
}
