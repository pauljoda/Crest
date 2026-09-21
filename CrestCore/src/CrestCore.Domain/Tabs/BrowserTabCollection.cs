namespace CrestCore.Domain;

/// Organization of tab values, independent of profiles, authorization and live
/// page lifetimes. BrowserSpace applies its access rules before editing this collection.
public sealed partial class BrowserTabCollection {
    #region Variables

    public const int MaximumTabs = BrowserSpace.MaximumTabs;
    private readonly List<BrowserTab> tabs = [];
    private readonly List<BrowserFolder> folders = [];
    private readonly List<ArchivedTab> archive = [];
    internal List<BrowserTab> MutableTabs => tabs;
    internal List<BrowserFolder> MutableFolders => folders;
    internal List<ArchivedTab> MutableArchive => archive;
    public IReadOnlyList<BrowserTab> Tabs => tabs.AsReadOnly();
    public IReadOnlyList<BrowserFolder> Folders => folders.AsReadOnly();
    public IReadOnlyList<ArchivedTab> Archive => archive.AsReadOnly();

    #endregion

    #region Actions - Persistence

    public static BrowserTabCollection Restore(SpaceState state) {
        var collection = new BrowserTabCollection();
        collection.tabs.AddRange(state.Tabs.Select(BrowserTab.Restore));
        collection.folders.AddRange(state.Folders.Select(f => new BrowserFolder(f.Id, f.Name, f.Location,
            f.ParentId, f.IsCollapsed, f.CollapseModifiedAt, f.OrderAnchorTabId)));
        collection.archive.AddRange(state.Archive.Select(a => new ArchivedTab(a.Tab, a.ClosedAt, a.Reason)));
        new FolderTree(collection.folders).Validate();
        collection.RepairSplitMembership();
        return collection;
    }

    public SpaceState Capture(SpaceState original, TabId? selected) => original with {
        Tabs = tabs.Select(t => t.Capture()).ToArray(),
        Folders = folders.Select(f => new FolderState(f.Id, f.Name, f.Location, f.ParentId,
            f.IsCollapsed, f.CollapseModifiedAt, f.OrderAnchorTabId)).ToArray(),
        Archive = archive.Select(a => new ArchiveState(a.Tab, a.ClosedAt, a.Reason)).ToArray(),
        SelectedTabId = selected
    };

    #endregion

    #region Mutators

    public BrowserTab Tab(TabId id) => tabs.Find(t => t.Id == id) ?? throw new BrowserRuleException("unknown_tab");

    #endregion
}
