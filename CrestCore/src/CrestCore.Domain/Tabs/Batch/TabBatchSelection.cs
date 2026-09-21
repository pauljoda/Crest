namespace CrestCore.Domain;

public sealed record TabBatchSelection(IReadOnlyList<BatchItem> Roots, IReadOnlyList<BatchTab> Tabs,
    IReadOnlyList<BatchFolder> Folders) {
    #region Actions - Batch

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

    #endregion
}
