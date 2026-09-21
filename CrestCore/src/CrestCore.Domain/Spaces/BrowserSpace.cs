namespace CrestCore.Domain;

public sealed partial class BrowserSpace {

    #region Variables

    // Collections
    private readonly BrowserTabCollection collection = new();

    private List<BrowserTab> tabs => collection.MutableTabs;

    public IReadOnlyList<BrowserTab> Tabs => tabs.AsReadOnly();

    private List<BrowserFolder> folders => collection.MutableFolders;

    public IReadOnlyList<BrowserFolder> Folders => folders.AsReadOnly();

    private List<ArchivedTab> archive => collection.MutableArchive;

    public IReadOnlyList<ArchivedTab> Archive => archive.AsReadOnly();

    private readonly List<HistoryVisit> history = [];

    public IReadOnlyList<HistoryVisit> History => history.AsReadOnly();

    // Identity and selection
    public SpaceId Id { get; }

    public ProfileId ProfileId { get; }

    public TabId? RestoredSelection { get; private set; }

    // Preferences and display
    public SearchPreferences Search { get; private set; } = SearchPreferences.Default;

    public string Name { get; private set; }

    // Access state
    private bool unlocked;

    public bool RequiresAuthentication { get; private set; }

    public bool SupportsDeviceAuthentication { get; private set; } = true;

    public bool IsLocked => RequiresAuthentication && !unlocked;

    public bool IsDeleting { get; private set; }

    public ulong AccessGeneration { get; private set; } = 1;

    // Limits
    public const int MaximumTabs = 5000;

    #endregion

    #region Constructors

    public BrowserSpace(SpaceId id, ProfileId profileId, string name) {
        Id = id;
        ProfileId = profileId;
        Name = name;
    }

    #endregion

    #region Actions - Access

    internal void BeginDeletion() { IsDeleting = true; Lock(); }

    public void Lock() { unlocked = false; AccessGeneration++; }

    public void Unlock(ProfileId profile, ulong generation) {
        if (!SupportsDeviceAuthentication) throw new BrowserRuleException("unsupported_access_policy");
        if (ProfileId != profile || AccessGeneration != generation) throw new BrowserRuleException("stale_authentication");
        unlocked = true;
    }

    public void EnsureAccessible() {
        if (IsDeleting) throw new BrowserRuleException("space_deleting");
        if (IsLocked) throw new BrowserRuleException("space_locked");
    }

    public void ReconcileBorrowedPolicy(BrowserSpace source) {
        BorrowedProfilePolicy.RequireSource(Id, ProfileId, source.Id, source.ProfileId, !source.IsDeleting);
        Name = source.Name; Search = source.Search; Retention = source.Retention; ContentBlocking = source.ContentBlocking;
        RequiresAuthentication = source.RequiresAuthentication;
        SupportsDeviceAuthentication = source.SupportsDeviceAuthentication;
        unlocked = !source.IsLocked; AccessGeneration = source.AccessGeneration;
    }

    #endregion

    #region Actions - Tabs

    public void Add(BrowserTab tab, TabId? after) {
        if (tabs.Count >= MaximumTabs) throw new BrowserRuleException("tab_limit");
        if (tabs.Any(t => t.Id == tab.Id)) throw new BrowserRuleException("duplicate_tab");
        int index = after is null ? -1 : tabs.FindIndex(t => t.Id == after);
        tabs.Insert(index < 0 ? tabs.Count : index + 1, tab);
    }

    public void ValidateTransferFrom(BrowserSpace source, TabId id) {
        EnsureAccessible(); source.EnsureAccessible();
        if (source == this || source.Id != Id || source.ProfileId != ProfileId) throw new BrowserRuleException("wrong_profile");
        if (tabs.Count >= MaximumTabs) throw new BrowserRuleException("tab_limit");
        if (tabs.Any(t => t.Id == id) || archive.Any(t => t.Id == id)) throw new BrowserRuleException("duplicate_tab");
        if (source.Tab(id).Phase is TabPhase.Creating or TabPhase.Closing or TabPhase.Unloading) throw new BrowserRuleException("page_busy");
    }

    public void AddOpenedTab(BrowserTab tab, TabId? after) {
        int lower = tabs.FindIndex(t => t.Placement == TabPlacement.Current);
        if (lower < 0) lower = tabs.Count;
        int insertion = lower;
        if (after is { } origin && tabs.Any(t => t.Id == origin))
            insertion = Math.Clamp(tabs.IndexOf(SplitMembers(origin)[^1]) + 1, lower, tabs.Count);
        Add(tab, null); tabs.Remove(tab); tabs.Insert(insertion, tab);
    }

    public void Remove(BrowserTab tab, DateTimeOffset now, bool archiveTab, string reason = "closed") {
        if (!tabs.Contains(tab)) throw new BrowserRuleException("unknown_tab");
        var orderedFolders = new FolderTree(folders).PreserveOrder([tab.Id], tabs);
        if (!tabs.Remove(tab)) throw new BrowserRuleException("unknown_tab");
        folders.Clear(); folders.AddRange(orderedFolders);
        if (reason != "autoCleanup") NormalizeSplits(now);
        if (archiveTab && !tab.Content.IsStartPage) {
            var state = tab.Capture() with { Placement = TabPlacement.Current, FolderId = null, SavedUrl = null, SplitGroupId = null };
            archive.Insert(0, new(state, now, reason));
        }
    }

    public void Place(TabId id, TabPlacement placement, FolderId? folder, DateTimeOffset? now = null) {
        EnsureAccessible();
        var tab = Tab(id);
        if (folder is not null && !folders.Any(f => f.Id == folder && f.Location == placement))
            throw new BrowserRuleException("invalid_folder_placement");
        if (placement == TabPlacement.Pinned && (folder is not null ||
            tab.Placement != TabPlacement.Pinned && tabs.Count(t => t.Placement == TabPlacement.Pinned) >= 12))
            throw new BrowserRuleException("pinned_limit");
        var nextFolders = new FolderTree(folders).PreserveOrder([tab.Id], tabs);
        var remaining = tabs.Where(t => t.Id != id).ToList();
        int last = remaining.FindLastIndex(t => t.Placement == placement && t.FolderId == folder);
        int insertion = last >= 0 ? last + 1 : placement switch {
            TabPlacement.Pinned => remaining.FindIndex(t => t.Placement != TabPlacement.Pinned),
            TabPlacement.Saved => remaining.FindIndex(t => t.Placement == TabPlacement.Current),
            _ => remaining.Count
        };
        if (insertion < 0) insertion = remaining.Count;
        tab.Place(placement, folder, now, preservesSplit: true);
        if (now is { } changed) tab.MarkPosition(changed);
        remaining.Insert(insertion, tab); tabs.Clear(); tabs.AddRange(remaining);
        folders.Clear(); folders.AddRange(nextFolders); RepairSplitMembership();
    }

    #endregion

    #region Actions - History and archive

    public void RecordVisit(BrowserTab tab, DateTimeOffset now, IIdSource ids) {
        if (tab.Url is null || tab.Failure is not null || !Uri.TryCreate(tab.Url, UriKind.Absolute, out var uri)
            || uri.Scheme is not ("http" or "https")) return;
        string url = HistoryPolicy.Normalize(tab.Url)!;
        var old = history.Find(h => h.Url == url);
        if (old is not null) history.Remove(old);
        history.Insert(0, HistoryPolicy.Record(url, tab.Title, now, old?.Id ?? ids.Next(), old));
        if (history.Count > HistoryPolicy.MaximumEntries)
            history.RemoveRange(HistoryPolicy.MaximumEntries, history.Count - HistoryPolicy.MaximumEntries);
    }

    public BrowserTab RestoreArchived(TabId id, DateTimeOffset now) {
        var archived = archive.Find(a => a.Id == id) ?? throw new BrowserRuleException("unknown_archive");
        var tab = BrowserTab.Restore(archived.Tab with {
            Placement = TabPlacement.Current,
            FolderId = null,
            SplitGroupId = null,
            SavedUrl = null,
            LastActivatedAt = now,
            PositionModifiedAt = BrowserEditTimestamp.Normalize(now)
        });
        Add(tab, null); archive.Remove(archived); return tab;
    }

    #endregion

    #region Actions - Persistence

    public static BrowserSpace Restore(SpaceState state) {
        var space = new BrowserSpace(state.Id, state.ProfileId, ValidName(state.Name)) { RequiresAuthentication = state.RequiresAuthentication, SupportsDeviceAuthentication = state.SupportsDeviceAuthentication, RestoredSelection = state.SelectedTabId, Search = state.Search ?? SearchPreferences.Default, Retention = state.Retention ?? RetentionPreferences.Default, ContentBlocking = state.ContentBlocking };
        foreach (var folder in state.Folders) space.folders.Add(new(folder.Id, folder.Name, folder.Location, folder.ParentId,
            folder.IsCollapsed, folder.CollapseModifiedAt, folder.OrderAnchorTabId));
        new FolderTree(space.folders).Validate();
        foreach (var tab in state.Tabs) space.Add(BrowserTab.Restore(tab), null);
        // Repair malformed runs without dissolving a singleton from an incomplete sync batch.
        space.RepairSplitMembership();
        space.archive.AddRange(state.Archive.Select(a => new ArchivedTab(a.Tab, a.ClosedAt, a.Reason)));
        space.history.AddRange(state.History);
        return space;
    }

    public SpaceState Capture(TabId? selected) => new(Id, ProfileId, Name, RequiresAuthentication,
        tabs.Select(t => t.Capture()).ToArray(), folders.Select(f => new FolderState(f.Id, f.Name, f.Location, f.ParentId,
            f.IsCollapsed, f.CollapseModifiedAt, f.OrderAnchorTabId)).ToArray(),
        archive.Select(a => new ArchiveState(a.Tab, a.ClosedAt, a.Reason)).ToArray(), history.ToArray(), selected, Search, SupportsDeviceAuthentication, Retention, ContentBlocking);

    #endregion

    #region Actions - Validation

    public static string ValidName(string name) {
        name = name.Trim();
        if (name.Length is 0 or > 200) throw new BrowserRuleException("invalid_name");
        return name;
    }

    public static void ValidateUrl(string? url, bool allowsInternalPages = false) {
        if (url is null || url.Length > 16384 || !Uri.TryCreate(url, UriKind.Absolute, out var parsed)
            || (parsed.Scheme is not ("http" or "https") && url != "about:blank"
                // A local document is a legitimate tab URL on every engine. It stays
                // out of sync, which the sync projection decides by scheme, not here.
                && !(parsed.Scheme == "file" && parsed.Host.Length == 0 && parsed.AbsolutePath.Length > 0)
                && !(allowsInternalPages && parsed.Scheme is "chrome" or "crest" && parsed.Host.Length > 0)
                && !(allowsInternalPages && parsed.Scheme == "chrome-extension" && parsed.Host.Length == 32
                    && parsed.Host.All(c => c is >= 'a' and <= 'p')))
            || !string.IsNullOrEmpty(parsed.UserInfo))
            throw new BrowserRuleException("unsupported_url");
    }

    #endregion

    #region Mutators

    #region Name

    public void Rename(string name) { EnsureAccessible(); Name = ValidName(name); }

    #endregion

    #region Access state

    public void SetAccessPolicy(bool requiresAuthentication) {
        EnsureAccessible();
        RequiresAuthentication = requiresAuthentication;
        Lock();
    }

    #endregion

    #region Search preferences

    public void SetSearch(SearchPreferences search) { EnsureAccessible(); Search = search; }

    #endregion

    #region Restored selection

    internal void RemovedSelection(TabId tab) { if (RestoredSelection == tab) RestoredSelection = null; }

    #endregion

    #region Collection views

    public BrowserTab Tab(TabId id) => tabs.Find(t => t.Id == id) ?? throw new BrowserRuleException("unknown_tab");

    #endregion

    #endregion
}
