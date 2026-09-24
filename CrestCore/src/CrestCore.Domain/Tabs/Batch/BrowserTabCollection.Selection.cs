using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Types

    /// A tab or folder in the list the sidebar shows.
    private sealed record SidebarRow(Guid Id, bool IsFolder);

    #endregion

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
    /// counting from zero: the pinned tabs, then each section that holds
    /// folders, as `SectionOutline` lists it. Start Pages, which the sidebar
    /// does not list, have no place.
    private Dictionary<Guid, int> SidebarPositions() {
        var positions = new Dictionary<Guid, int>();
        var display = new FolderTree(folders).DisplayOrder();
        foreach (var placement in TabPlacement.All.OrderBy(placement => placement.Rank)) {
            BrowserTab[] listed = [.. tabs.Where(tab => tab.Placement == placement && !tab.Content.IsStartPage)];
            var outline = placement.HoldsFolders
                ? SectionOutline([.. display.Where(folder => folder.Location == placement)], listed)
                : listed.Select(tab => tab.Id);
            foreach (var id in outline) positions.TryAdd(id, positions.Count);
        }
        return positions;
    }

    /// One section's tabs and folders as the sidebar lists them. A folder
    /// takes the place of its first tab in the Space's order and lists its
    /// own folders and tabs there; a folder holding no tab keeps its place
    /// before the tab it anchors to, or else ends its list.
    private List<Guid> SectionOutline(IReadOnlyList<FolderState> sectionFolders, IReadOnlyList<BrowserTab> listed) {
        var paths = new Dictionary<Guid, Guid[]>();
        foreach (var folder in sectionFolders)
            paths[folder.Id] = [.. folder.ParentId is { } parent && paths.TryGetValue(parent, out var above) ? above : [], folder.Id];
        var top = new List<SidebarRow>();
        var nested = new Dictionary<Guid, List<SidebarRow>>();
        List<SidebarRow> Rows(Guid? parent) =>
            parent is not { } id ? top : nested.TryGetValue(id, out var rows) ? rows : nested[id] = [];
        var placed = new HashSet<Guid>();
        foreach (var tab in listed) {
            Guid? above = null;
            foreach (var folder in tab.FolderId is { } id && paths.TryGetValue(id, out var path) ? path : []) {
                if (placed.Add(folder)) Rows(above).Add(new(folder, IsFolder: true));
                above = folder;
            }
            Rows(tab.FolderId).Add(new(tab.Id, IsFolder: false));
        }
        foreach (var folder in sectionFolders.Where(folder => !placed.Contains(folder.Id))) {
            var rows = Rows(folder.ParentId);
            var anchor = folder.OrderAnchorTabId is { } anchored ? tabs.Find(tab => tab.Id == anchored) : null;
            var anchorPath = anchor?.FolderId is { } anchorFolder && paths.TryGetValue(anchorFolder, out var path) ? path : [];
            int index = anchor is null ? -1 : rows.FindIndex(row => row.IsFolder
                ? anchorPath.Contains(row.Id)
                : SplitMembers(row.Id).Any(member => member.Id == anchor.Id));
            rows.Insert(index < 0 ? rows.Count : index, new(folder.Id, IsFolder: true));
        }
        var outline = new List<Guid>();
        void List(IReadOnlyList<SidebarRow> rows) {
            foreach (var row in rows) {
                outline.Add(row.Id);
                if (row.IsFolder && nested.TryGetValue(row.Id, out var inside)) List(inside);
            }
        }
        List(top);
        return outline;
    }

    #endregion
}
