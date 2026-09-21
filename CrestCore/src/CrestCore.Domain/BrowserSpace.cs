namespace CrestCore.Domain;

public readonly record struct WorkspaceId(Guid Value);
public readonly record struct SpaceId(Guid Value);
public readonly record struct ProfileId(Guid Value);
public readonly record struct TabId(Guid Value);
public readonly record struct WindowId(Guid Value);
public readonly record struct PageId(Guid Value);
public readonly record struct FolderId(Guid Value);

public interface IIdSource { Guid Next(); }
public interface IClock { DateTimeOffset Now { get; } }
public sealed class SystemIdSource : IIdSource { public Guid Next() => Guid.NewGuid(); }
public sealed class SystemClock : IClock { public DateTimeOffset Now => DateTimeOffset.UtcNow; }

public sealed class BrowserRuleException(string code) : Exception(code)
{
    public string Code { get; } = code;
}

public enum TabKind { Web, Settings, StartPage, Native }
public enum TabPhase { Dormant, Creating, Ready, Unloading, Closing, Failed }
public enum TabPlacement { Current, Pinned, Saved }

public sealed class BrowserTab(TabId id, TabKind kind, string? url, PageId? pageId)
{
    public TabId Id { get; } = id;
    public TabKind Kind { get; private set; } = kind;
    public PageId? PageId { get; private set; } = pageId;
    public ulong Generation { get; private set; } = pageId is null ? 0UL : 1UL;
    public string? Url { get; private set; } = url;
    public string Title { get; private set; } = kind == TabKind.Settings ? "Settings" : kind == TabKind.StartPage ? "Start Page" : url ?? "New tab";
    public TabPhase Phase { get; private set; } = kind != TabKind.Web ? TabPhase.Ready : pageId is null ? TabPhase.Dormant : TabPhase.Creating;
    public TabPlacement Placement { get; private set; }
    public FolderId? FolderId { get; private set; }
    public bool IsLoading { get; private set; }
    public bool CanGoBack { get; private set; }
    public bool CanGoForward { get; private set; }
    public string? Failure { get; private set; }
    public string? SavedUrl { get; private set; }
    public string? CustomTitle { get; private set; }
    public string DisplayTitle => CustomTitle ?? Title;
    public DateTimeOffset LastActivatedAt { get; private set; }
    public DateTimeOffset? PositionModifiedAt { get; private set; }
    public DateTimeOffset? TitleModifiedAt { get; private set; }
    public bool KeepsPageLoaded { get; private set; }
    public Guid? SplitGroupId { get; private set; }
    public string? NativeKind { get; private set; } = kind == TabKind.Settings ? "settings" : null;

    public static BrowserTab Restore(TabState state)
    {
        var tab = new BrowserTab(state.Id, state.Kind, state.Url, null)
        {
            Title = state.Title, Placement = state.Placement, FolderId = state.FolderId,
            SavedUrl = state.SavedUrl, CustomTitle = string.IsNullOrWhiteSpace(state.CustomTitle) ? null : state.CustomTitle.Trim(),
            LastActivatedAt = state.LastActivatedAt, PositionModifiedAt = state.PositionModifiedAt,
            TitleModifiedAt = state.TitleModifiedAt, KeepsPageLoaded = state.KeepsPageLoaded,
            SplitGroupId = state.SplitGroupId, NativeKind = state.NativeKind
        };
        return tab;
    }
    public TabState Capture() => new(Id, Kind, Url, Title, Placement, FolderId, SavedUrl, CustomTitle,
        LastActivatedAt, PositionModifiedAt, TitleModifiedAt, KeepsPageLoaded, SplitGroupId, NativeKind);
    public void Activate(DateTimeOffset now) => LastActivatedAt = now;
    public void Rename(string? title, DateTimeOffset now)
    {
        title = title?.Trim();
        if (title?.Length > 4096) throw new BrowserRuleException("invalid_title");
        CustomTitle = string.IsNullOrEmpty(title) ? null : title; TitleModifiedAt = BrowserEditTimestamp.Normalize(now);
    }
    public void SetResidency(bool keepLoaded) => KeepsPageLoaded = keepLoaded;
    public void CreatePage(PageId page, bool allowsInternalPages = false)
    {
        if (Kind != TabKind.Web || Phase is not (TabPhase.Dormant or TabPhase.Failed))
            throw new BrowserRuleException("invalid_transition");
        BrowserSpace.ValidateUrl(Url, allowsInternalPages);
        PageId = page; Generation++; Phase = TabPhase.Creating; Failure = null;
    }

    public void NavigateStartPage(string url, PageId page, bool allowsInternalPages = false)
    {
        if (Kind != TabKind.StartPage || Placement != TabPlacement.Current)
            throw new BrowserRuleException("not_start_page_draft");
        BrowserSpace.ValidateUrl(url, allowsInternalPages);
        Kind = TabKind.Web; NativeKind = null; Url = url; Title = url;
        Phase = TabPhase.Dormant;
        CreatePage(page, allowsInternalPages);
    }

    public void Created()
    {
        if (Phase != TabPhase.Creating) throw new BrowserRuleException("invalid_transition");
        Phase = TabPhase.Ready;
    }

    public void Observe(string? url, string title, bool loading, bool back, bool forward, string? failure)
    {
        if (Phase == TabPhase.Creating) throw new BrowserRuleException("page_not_ready");
        if (url is not null) Url = url;
        Title = title; IsLoading = loading; CanGoBack = back; CanGoForward = forward; Failure = failure;
    }

    public void RequestClose()
    {
        if (Phase == TabPhase.Closing) throw new BrowserRuleException("already_closing");
        Phase = TabPhase.Closing;
    }

    public void RequestUnload()
    {
        if (Kind != TabKind.Web || Phase != TabPhase.Ready || KeepsPageLoaded || IsLoading)
            throw new BrowserRuleException("page_not_unloadable");
        Phase = TabPhase.Unloading;
    }
    public void CancelUnload()
    {
        if (Phase != TabPhase.Unloading) throw new BrowserRuleException("invalid_transition");
        Phase = TabPhase.Ready;
    }

    public void CancelClose() { Phase = TabPhase.Ready; }
    public void Unload(bool returnToSavedUrl = false)
    {
        PageId = null; IsLoading = false; CanGoBack = false; CanGoForward = false; Failure = null;
        Phase = Kind == TabKind.Web ? TabPhase.Dormant : TabPhase.Ready;
        if (returnToSavedUrl && SavedUrl is not null) Url = SavedUrl;
    }
    public void Fail(string reason) { Phase = TabPhase.Failed; Failure = reason; IsLoading = false; }
    internal void SetSplit(Guid? id) => SplitGroupId = id;
    internal void MarkPosition(DateTimeOffset now) => PositionModifiedAt = BrowserEditTimestamp.Normalize(now);
    public void Place(TabPlacement placement, FolderId? folder, DateTimeOffset? now = null, bool preservesSplit = false)
    {
        if (Placement == placement && FolderId == folder) return;
        if (placement != TabPlacement.Current) SavedUrl ??= Url;
        if (placement == TabPlacement.Current) SavedUrl = null;
        Placement = placement; FolderId = folder;
        if (!preservesSplit) SplitGroupId = null;
        if (now is { } changedAt) MarkPosition(changedAt);
    }
}

public sealed record BrowserFolder(FolderId Id, string Name, TabPlacement Location = TabPlacement.Saved,
    FolderId? ParentId = null, bool IsCollapsed = false, DateTimeOffset? CollapseModifiedAt = null, TabId? OrderAnchorTabId = null);
public sealed record ArchivedTab(TabState Tab, DateTimeOffset ClosedAt, string Reason)
{
    public TabId Id => Tab.Id;
}
public sealed record HistoryVisit(Guid Id, string Url, string Title, DateTimeOffset FirstVisitedAt,
    DateTimeOffset VisitedAt, int VisitCount);

public sealed partial class BrowserSpace(SpaceId id, ProfileId profileId, string name)
{
    public const int MaximumTabs = 5000;
    private readonly BrowserTabCollection collection = new();
    private List<BrowserTab> tabs => collection.MutableTabs;
    private List<BrowserFolder> folders => collection.MutableFolders;
    private List<ArchivedTab> archive => collection.MutableArchive;
    private readonly List<HistoryVisit> history = [];
    public SpaceId Id { get; } = id;
    public ProfileId ProfileId { get; } = profileId;
    public string Name { get; private set; } = name;
    public bool RequiresAuthentication { get; private set; }
    public bool SupportsDeviceAuthentication { get; private set; } = true;
    private bool unlocked;
    public bool IsLocked => RequiresAuthentication && !unlocked;
    public bool IsDeleting { get; private set; }
    internal void BeginDeletion() { IsDeleting = true; Lock(); }
    public ulong AccessGeneration { get; private set; } = 1;
    public void SetAccessPolicy(bool requiresAuthentication)
    {
        EnsureAccessible();
        RequiresAuthentication = requiresAuthentication;
        Lock();
    }
    public void Lock() { unlocked = false; AccessGeneration++; }
    public void Unlock(ProfileId profile, ulong generation)
    {
        if (!SupportsDeviceAuthentication) throw new BrowserRuleException("unsupported_access_policy");
        if (ProfileId != profile || AccessGeneration != generation) throw new BrowserRuleException("stale_authentication");
        unlocked = true;
    }
    public SearchPreferences Search { get; private set; } = SearchPreferences.Default;
    public void SetSearch(SearchPreferences search) { EnsureAccessible(); Search = search; }
    public TabId? RestoredSelection { get; private set; }
    internal void RemovedSelection(TabId tab) { if (RestoredSelection == tab) RestoredSelection = null; }
    public IReadOnlyList<BrowserTab> Tabs => tabs.AsReadOnly();
    public IReadOnlyList<BrowserFolder> Folders => folders.AsReadOnly();
    public IReadOnlyList<ArchivedTab> Archive => archive.AsReadOnly();
    public IReadOnlyList<HistoryVisit> History => history.AsReadOnly();
    public void Rename(string name) { EnsureAccessible(); Name = ValidName(name); }
    public BrowserTab Tab(TabId id) => tabs.Find(t => t.Id == id) ?? throw new BrowserRuleException("unknown_tab");
    public void Add(BrowserTab tab, TabId? after)
    {
        if (tabs.Count >= MaximumTabs) throw new BrowserRuleException("tab_limit");
        if (tabs.Any(t => t.Id == tab.Id)) throw new BrowserRuleException("duplicate_tab");
        int index = after is null ? -1 : tabs.FindIndex(t => t.Id == after);
        tabs.Insert(index < 0 ? tabs.Count : index + 1, tab);
    }
    public void ValidateTransferFrom(BrowserSpace source, TabId id)
    {
        EnsureAccessible(); source.EnsureAccessible();
        if (source == this || source.Id != Id || source.ProfileId != ProfileId) throw new BrowserRuleException("wrong_profile");
        if (tabs.Count >= MaximumTabs) throw new BrowserRuleException("tab_limit");
        if (tabs.Any(t => t.Id == id) || archive.Any(t => t.Id == id)) throw new BrowserRuleException("duplicate_tab");
        if (source.Tab(id).Phase is TabPhase.Creating or TabPhase.Closing or TabPhase.Unloading) throw new BrowserRuleException("page_busy");
    }
    public void AddOpenedTab(BrowserTab tab, TabId? after)
    {
        int lower = tabs.FindIndex(t => t.Placement == TabPlacement.Current);
        if (lower < 0) lower = tabs.Count;
        int insertion = lower;
        if (after is { } origin && tabs.Any(t => t.Id == origin))
            insertion = Math.Clamp(tabs.IndexOf(SplitMembers(origin)[^1]) + 1, lower, tabs.Count);
        Add(tab, null); tabs.Remove(tab); tabs.Insert(insertion, tab);
    }
    public void Remove(BrowserTab tab, DateTimeOffset now, bool archiveTab, string reason = "closed")
    {
        if (!tabs.Contains(tab)) throw new BrowserRuleException("unknown_tab");
        var orderedFolders = new FolderTree(folders).PreserveOrder([tab.Id], tabs);
        if (!tabs.Remove(tab)) throw new BrowserRuleException("unknown_tab");
        folders.Clear(); folders.AddRange(orderedFolders);
        if (reason != "autoCleanup") NormalizeSplits(now);
        if (archiveTab && tab.Kind != TabKind.StartPage)
        {
            var state = tab.Capture() with { Placement = TabPlacement.Current, FolderId = null, SavedUrl = null, SplitGroupId = null };
            archive.Insert(0, new(state, now, reason));
        }
    }
    public void RecordVisit(BrowserTab tab, DateTimeOffset now, IIdSource ids)
    {
        if (tab.Url is null || tab.Failure is not null || !Uri.TryCreate(tab.Url, UriKind.Absolute, out var uri)
            || uri.Scheme is not ("http" or "https")) return;
        string url = HistoryPolicy.Normalize(tab.Url)!;
        var old = history.Find(h => h.Url == url);
        if (old is not null) history.Remove(old);
        history.Insert(0, HistoryPolicy.Record(url, tab.Title, now, old?.Id ?? ids.Next(), old));
        if (history.Count > HistoryPolicy.MaximumEntries)
            history.RemoveRange(HistoryPolicy.MaximumEntries, history.Count - HistoryPolicy.MaximumEntries);
    }
    public BrowserTab RestoreArchived(TabId id, DateTimeOffset now)
    {
        var archived = archive.Find(a => a.Id == id) ?? throw new BrowserRuleException("unknown_archive");
        var tab = BrowserTab.Restore(archived.Tab with
        { Placement = TabPlacement.Current, FolderId = null, SplitGroupId = null, SavedUrl = null,
            LastActivatedAt = now, PositionModifiedAt = BrowserEditTimestamp.Normalize(now) });
        Add(tab, null); archive.Remove(archived); return tab;
    }
    public void Place(TabId id, TabPlacement placement, FolderId? folder, DateTimeOffset? now = null)
    {
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
        int insertion = last >= 0 ? last + 1 : placement switch
        {
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
    public void EnsureAccessible()
    {
        if (IsDeleting) throw new BrowserRuleException("space_deleting");
        if (IsLocked) throw new BrowserRuleException("space_locked");
    }
    public void ReconcileBorrowedPolicy(BrowserSpace source)
    {
        BorrowedProfilePolicy.RequireSource(Id, ProfileId, source.Id, source.ProfileId, !source.IsDeleting);
        Name = source.Name; Search = source.Search; Retention = source.Retention; ContentBlocking = source.ContentBlocking;
        RequiresAuthentication = source.RequiresAuthentication;
        SupportsDeviceAuthentication = source.SupportsDeviceAuthentication;
        unlocked = !source.IsLocked; AccessGeneration = source.AccessGeneration;
    }
    public static BrowserSpace Restore(SpaceState state)
    {
        var space = new BrowserSpace(state.Id, state.ProfileId, ValidName(state.Name))
        { RequiresAuthentication = state.RequiresAuthentication, SupportsDeviceAuthentication = state.SupportsDeviceAuthentication, RestoredSelection = state.SelectedTabId, Search = state.Search ?? SearchPreferences.Default, Retention = state.Retention ?? RetentionPreferences.Default, ContentBlocking = state.ContentBlocking };
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
    public static string ValidName(string name)
    {
        name = name.Trim();
        if (name.Length is 0 or > 200) throw new BrowserRuleException("invalid_name");
        return name;
    }
    public static void ValidateUrl(string? url, bool allowsInternalPages = false)
    {
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
}
