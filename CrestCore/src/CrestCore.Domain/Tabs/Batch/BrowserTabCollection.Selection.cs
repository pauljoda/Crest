using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Selection

    /// `selection` resolved in this Space: a picked tab or folder inside a
    /// picked folder goes with that folder, and the rest are ordered as the
    /// sidebar lists them. Refused with `SelectionChanged` when it picks
    /// nothing, picks one tab or folder twice or one the Space does not hold,
    /// holds a Start Page, or holds other tabs than the window saw.
    public SelectedTabs Select(TabSelection selection) {
        ArgumentNullException.ThrowIfNull(selection);
        IReadOnlyList<Guid> picked = [.. selection.TabIds, .. selection.FolderIds];
        if (picked.Count == 0 || picked.Distinct().Count() != picked.Count
            || selection.FolderIds.Any(id => folders.All(folder => folder.Id != id))
            || selection.TabIds.Any(id => tabs.All(tab => tab.Id != id)))
            throw new Rejected(new SelectionChanged());
        var tree = new FolderTree(folders);
        var subtrees = selection.FolderIds.ToDictionary(id => id, tree.Subtree);
        var covered = subtrees.SelectMany(entry => entry.Value.Where(id => id != entry.Key)).ToHashSet();
        var held = subtrees.Values.SelectMany(subtree => subtree).ToHashSet();
        var positions = SidebarPositions();
        SelectedTabs.Root[] roots = [
            .. selection.FolderIds.Where(id => !covered.Contains(id)).Select(id => new SelectedTabs.Root(id, IsFolder: true)),
            .. selection.TabIds.Where(id => Tab(id).FolderId is not { } folder || !held.Contains(folder))
                .Select(id => new SelectedTabs.Root(id, IsFolder: false))
        ];
        roots = [.. roots.OrderBy(root => positions.GetValueOrDefault(root.Id, int.MaxValue))];
        BrowserTab[] members = [.. roots.SelectMany(root => root.IsFolder
            ? tabs.Where(tab => tab.FolderId is { } folder && subtrees[root.Id].Contains(folder))
            : [Tab(root.Id)])];
        var seen = selection.MemberTabIds.ToHashSet();
        if (members.Any(tab => tab.Content.IsStartPage) || seen.Count != selection.MemberTabIds.Count || members.Length != seen.Count
            || !members.All(tab => seen.Contains(tab.Id)))
            throw new Rejected(new SelectionChanged());
        return new(roots, held, members);
    }

    /// Where each tab and folder falls in the list the Space's sidebar shows,
    /// counting from zero, as its outline orders them. Start Pages, which the
    /// sidebar does not list, have no place.
    private Dictionary<Guid, int> SidebarPositions() => SidebarOutline.Of(TabStates, folders).Positions();

    #endregion
}
