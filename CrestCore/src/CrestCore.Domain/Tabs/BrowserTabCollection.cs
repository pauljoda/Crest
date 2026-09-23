using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A Space's organization while one edit applies to it: its tabs, folders, split
/// metadata and the tabs the edit archives. It is restored from the Space's stored
/// records and captured back into them, independent of profiles, authorization and
/// live pages. The archive holds only what this edit adds; existing archive records
/// stay with the Space.
public sealed partial class BrowserTabCollection {
    #region Variables

    public const int MaximumTabs = BrowserSpace.MaximumTabs;
    private readonly List<BrowserTab> tabs = [];
    private readonly List<FolderState> folders = [];
    private readonly List<SplitGroupState> splitGroups = [];
    private readonly List<ArchivedTabState> archive = [];
    public IReadOnlyList<BrowserTab> Tabs => tabs.AsReadOnly();
    public IReadOnlyList<FolderState> Folders => folders.AsReadOnly();
    public IReadOnlyList<SplitGroupState> SplitGroups => splitGroups.AsReadOnly();
    public IReadOnlyList<ArchivedTabState> Archive => archive.AsReadOnly();
    public IReadOnlyList<TabState> TabStates => tabs.Select(tab => tab.State).ToArray();

    #endregion

    #region Actions - Persistence

    public static BrowserTabCollection Restore(IEnumerable<TabState> tabs, IEnumerable<FolderState> folders,
        IEnumerable<SplitGroupState> splitGroups) {
        var collection = new BrowserTabCollection();
        collection.tabs.AddRange(tabs.Select(BrowserTab.Restore));
        collection.folders.AddRange(folders);
        collection.splitGroups.AddRange(splitGroups);
        new FolderTree(collection.folders).Validate();
        collection.RepairSplitMembership();
        return collection;
    }

    #endregion

    #region Mutators

    public BrowserTab Tab(Guid id) => tabs.Find(t => t.Id == id) ?? throw new BrowserRuleException(BrowserRuleCodes.UnknownTab);

    #endregion
}
