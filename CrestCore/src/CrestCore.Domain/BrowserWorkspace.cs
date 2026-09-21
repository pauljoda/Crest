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
        CustomTitle = string.IsNullOrEmpty(title) ? null : title; TitleModifiedAt = now;
    }
    public void SetResidency(bool keepLoaded) => KeepsPageLoaded = keepLoaded;
    public void CreatePage(PageId page, bool allowsInternalPages = false)
    {
        if (Kind != TabKind.Web || Phase is not (TabPhase.Dormant or TabPhase.Failed))
            throw new BrowserRuleException("invalid_transition");
        BrowserWorkspace.ValidateUrl(Url, allowsInternalPages);
        PageId = page; Generation++; Phase = TabPhase.Creating; Failure = null;
    }

    public void NavigateStartPage(string url, PageId page, bool allowsInternalPages = false)
    {
        if (Kind != TabKind.StartPage || Placement != TabPlacement.Current)
            throw new BrowserRuleException("not_start_page_draft");
        BrowserWorkspace.ValidateUrl(url, allowsInternalPages);
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
    internal void MarkPosition(DateTimeOffset now) => PositionModifiedAt = now;
    public void Place(TabPlacement placement, FolderId? folder, DateTimeOffset? now = null, bool preservesSplit = false)
    {
        if (Placement == placement && FolderId == folder) return;
        if (placement != TabPlacement.Current) SavedUrl ??= Url;
        if (placement == TabPlacement.Current) SavedUrl = null;
        Placement = placement; FolderId = folder;
        if (!preservesSplit) SplitGroupId = null;
        if (now is not null) PositionModifiedAt = now;
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
            LastActivatedAt = now, PositionModifiedAt = now });
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
}

public sealed class BrowserWindow(WindowId id, SpaceId spaceId)
{
    private readonly Dictionary<SpaceId, TabId?> selections = [];
    public WindowId Id { get; } = id;
    public SpaceId SpaceId { get; private set; } = spaceId;
    public string? PlatformSceneId { get; private set; }
    public void BindScene(string id) => PlatformSceneId = id;
    // A missing selection and an explicitly empty selection are different durable states.
    public IReadOnlyDictionary<SpaceId, TabId?> Selections => selections.AsReadOnly();
    public TabId? Selection(SpaceId space) => selections.GetValueOrDefault(space);
    public void Select(SpaceId space, TabId? tab) { SpaceId = space; selections[space] = tab; }
    public void Switch(SpaceId space) { SpaceId = space; selections.TryAdd(space, null); }
    public void Removed(SpaceId space, TabId tab, TabId? fallback)
    {
        if (selections.TryGetValue(space, out var selected) && selected == tab) selections[space] = fallback;
    }
    internal void RemovedSpace(SpaceId space, SpaceId replacement)
    {
        selections.Remove(space);
        if (SpaceId == space) Switch(replacement);
    }
}

/// The semantic writer for one workspace. Native page objects never enter this aggregate.
public sealed partial class BrowserWorkspace(WorkspaceId id, IIdSource ids, IClock clock, bool allowsInternalPages = false)
{
    public const int MaximumSpaces = 64;
    private readonly List<BrowserSpace> spaces = [];
    private readonly List<BrowserWindow> windows = [];
    private readonly List<SpaceDeletionState> deletions = [];
    public IReadOnlyList<SpaceDeletionState> SpaceDeletions => deletions.AsReadOnly();
    public WorkspaceId Id { get; } = id;
    public SpaceId? DefaultSpaceId { get; private set; }
    public SpaceId? RestoredSpaceId { get; private set; }
    private readonly Dictionary<WindowId, WindowState> restoredWindows = [];
    public IReadOnlyList<BrowserSpace> Spaces => spaces.AsReadOnly();
    public IReadOnlyList<BrowserWindow> Windows => windows.AsReadOnly();
    public BrowserSpace Space(SpaceId id) => spaces.Find(s => s.Id == id) ?? throw new BrowserRuleException("unknown_space");
    public BrowserWindow Window(WindowId id) => windows.Find(w => w.Id == id) ?? throw new BrowserRuleException("unknown_window");
    public BrowserSpace AddSpace(string name, bool privateBrowsing = false)
    {
        if (spaces.Count(s => !s.IsDeleting) >= MaximumSpaces) throw new BrowserRuleException("space_limit");
        var space = new BrowserSpace(new(ids.Next()), new(ids.Next()), BrowserSpace.ValidName(name));
        if (privateBrowsing)
        {
            space.SetSearch(SearchPreferences.Default.Select("duckDuckGo", false));
            space.SetRetention(RetentionPreferences.Default with { CurrentTabs = CurrentTabCleanup.Never });
        }
        spaces.Add(space); DefaultSpaceId ??= space.Id; return space;
    }
    public void BeginSpaceDeletion(SpaceId id)
    {
        var space = Space(id); space.EnsureAccessible();
        var available = spaces.Where(s => !s.IsDeleting && s.Id != id).ToArray();
        if (available.Length == 0) throw new BrowserRuleException("cannot_delete_last_space");
        var index = spaces.IndexOf(space);
        var replacement = available.FirstOrDefault(s => spaces.IndexOf(s) > index) ?? available[^1];
        space.BeginDeletion();
        deletions.Add(new(id, space.ProfileId, clock.Now));
        RemoveSpaceSelections(id, replacement.Id);
    }
    private void RemoveSpaceSelections(SpaceId id, SpaceId replacement)
    {
        foreach (var window in windows) window.RemovedSpace(id, replacement);
        foreach (var window in restoredWindows.Values.ToArray())
        {
            var selections = window.Selections.Where(s => s.Key != id).ToDictionary();
            restoredWindows[window.Id] = window with
            { SpaceId = window.SpaceId == id ? replacement : window.SpaceId, Selections = selections };
        }
        if (DefaultSpaceId == id) DefaultSpaceId = replacement;
        if (RestoredSpaceId == id) RestoredSpaceId = replacement;
    }
    public void CompleteSpaceDeletion(SpaceId id, ProfileId profile)
    {
        var index = deletions.FindIndex(d => d.Space == id && d.Profile == profile && !d.Completed);
        if (index < 0 || Space(id).ProfileId != profile) throw new BrowserRuleException("stale_space_deletion");
        spaces.Remove(Space(id)); deletions[index] = deletions[index] with { Completed = true };
    }
    public BrowserWindow AddWindow(WindowId id)
    {
        if (windows.Any(w => w.Id == id)) throw new BrowserRuleException("duplicate_window");
        if (spaces.Count == 0) throw new BrowserRuleException("empty_session");
        var firstSpace = RestoredSpaceId ?? DefaultSpaceId ?? spaces[0].Id;
        var window = new BrowserWindow(id, firstSpace);
        if (restoredWindows.Remove(id, out var restored))
        {
            foreach (var selection in restored.Selections) window.Select(selection.Key, selection.Value);
            window.Switch(restored.SpaceId);
            if (restored.PlatformSceneId is { } scene) window.BindScene(scene);
        }
        else window.Select(firstSpace, null);
        // Older window snapshots may name the same page. First restoration owns
        // its presentation; later windows retain an explicit empty selection.
        if (window.Selection(window.SpaceId) is { } selected && PresentingWindow(window.SpaceId, selected) is not null)
            window.Select(window.SpaceId, null);
        windows.Add(window); return window;
    }
    public bool HasWindow(WindowId id) => windows.Any(w => w.Id == id) || restoredWindows.ContainsKey(id);
    public void CloseWindow(WindowId id)
    {
        if (restoredWindows.Remove(id)) return;
        windows.Remove(Window(id));
    }
    public void BindWindowScene(WindowId id, string sceneId)
    {
        if (sceneId.Length is 0 or > 512) throw new BrowserRuleException("invalid_scene_id");
        if (windows.Any(w => w.Id != id && w.PlatformSceneId == sceneId)
            || restoredWindows.Values.Any(w => w.Id != id && w.PlatformSceneId == sceneId))
            throw new BrowserRuleException("duplicate_scene_id");
        Window(id).BindScene(sceneId);
    }
    public BrowserTab Open(WindowId windowId, SpaceId spaceId, string? url, TabKind kind, bool foreground)
    {
        var window = Window(windowId); var space = Space(spaceId);
        space.EnsureAccessible();
        if (kind == TabKind.Web) ValidateUrl(url, allowsInternalPages);
        var tab = new BrowserTab(new(ids.Next()), kind, url, kind == TabKind.Web ? new PageId(ids.Next()) : null);
        space.AddOpenedTab(tab, window.Selection(spaceId));
        tab.Activate(clock.Now);
        if (foreground) window.Select(spaceId, tab.Id);
        return tab;
    }
    public void Select(WindowId windowId, SpaceId spaceId, TabId? tabId)
    {
        var space = Space(spaceId);
        space.EnsureAccessible();
        if (tabId is { } tab) _ = space.Tab(tab);
        // Direct selection cannot grant a second presentation owner. The application
        // coordinates a native detach before calling TransferPresentation.
        if (tabId is { } requested && PresentingWindow(spaceId, requested) is { } owner && owner.Id != windowId)
            throw new BrowserRuleException("page_presented_in_another_window");
        Window(windowId).Select(spaceId, tabId);
        if (tabId is { } selected) space.Tab(selected).Activate(clock.Now);
    }
    public void Switch(WindowId windowId, SpaceId spaceId)
    {
        var space = Space(spaceId);
        var window = Window(windowId);
        if (space.IsLocked) { window.Switch(spaceId); return; }
        Select(windowId, spaceId, window.Selection(spaceId));
    }
    public BrowserWindow? PresentingWindow(SpaceId spaceId, TabId tabId)
    {
        var members = Space(spaceId).SplitMembers(tabId).Select(t => t.Id).ToHashSet();
        return windows.SingleOrDefault(w => w.SpaceId == spaceId && w.Selection(spaceId) is { } selected && members.Contains(selected));
    }
    public IReadOnlyList<BrowserTab> PresentedTabs(WindowId windowId)
    {
        var window = Window(windowId); var space = Space(window.SpaceId);
        return window.Selection(space.Id) is { } selected && !space.IsLocked && !space.IsDeleting ? space.SplitMembers(selected) : [];
    }
    public void TransferPresentation(WindowId sourceId, WindowId destinationId, SpaceId spaceId, TabId tabId)
    {
        var source = Window(sourceId); var destination = Window(destinationId); var space = Space(spaceId);
        space.EnsureAccessible(); var tab = space.Tab(tabId);
        if (sourceId == destinationId || PresentingWindow(spaceId, tabId)?.Id != sourceId
            || space.SplitMembers(tabId).Any(t => t.Phase == TabPhase.Closing)) throw new BrowserRuleException("stale_presentation_transfer");
        source.Select(spaceId, null); destination.Select(spaceId, tabId); tab.Activate(clock.Now);
    }
    public IReadOnlySet<TabId> ProtectedTabs(SpaceId spaceId)
    {
        var space = Space(spaceId);
        var selected = windows.Select(w => w.Selections).Concat(restoredWindows.Values.Select(w => w.Selections))
            .Where(s => s.TryGetValue(spaceId, out var id) && id is not null).Select(s => s[spaceId]!.Value);
        return selected.Where(id => space.Tabs.Any(t => t.Id == id)).SelectMany(id => space.SplitMembers(id)).Select(t => t.Id).ToHashSet();
    }
    public void Close(SpaceId spaceId, TabId tabId, bool delete = false, bool returnToSavedUrl = false, string reason = "closed")
    {
        var space = Space(spaceId); var tab = space.Tab(tabId);
        int index = space.Tabs.ToList().IndexOf(tab);
        if (tab.Placement == TabPlacement.Current || delete) space.Remove(tab, clock.Now, true, reason);
        else tab.Unload(returnToSavedUrl);
        space.RemovedSelection(tabId);
        foreach (var restored in restoredWindows.Values.ToArray())
        {
            if (restored.Selections.GetValueOrDefault(spaceId) != tabId) continue;
            var selections = new Dictionary<SpaceId, TabId?>(restored.Selections) { [spaceId] = null };
            restoredWindows[restored.Id] = restored with { Selections = selections };
        }
        var candidates = space.Tabs.Take(index).Reverse().Concat(space.Tabs.Skip(index)).Where(t => t.Id != tabId).ToArray();
        foreach (var window in windows)
        {
            var fallback = candidates.FirstOrDefault(candidate => PresentingWindow(spaceId, candidate.Id) is not { } owner || owner.Id == window.Id);
            window.Removed(spaceId, tabId, fallback?.Id);
        }
    }
    public BrowserTab RestoreArchived(WindowId windowId, SpaceId spaceId, TabId tabId)
    {
        var window = Window(windowId); var space = Space(spaceId); space.EnsureAccessible();
        var tab = space.RestoreArchived(tabId, clock.Now); window.Select(spaceId, tab.Id); return tab;
    }
    public void TransferTabTo(BrowserWorkspace destination, SpaceId spaceId, TabId tabId, WindowId destinationWindow)
    {
        var source = Space(spaceId); var target = destination.Space(spaceId);
        target.ValidateTransferFrom(source, tabId); var window = destination.Window(destinationWindow);
        var tab = source.Tab(tabId);
        source.Remove(tab, clock.Now, archiveTab: false); source.RemovedSelection(tabId);
        foreach (var sourceWindow in windows) sourceWindow.Removed(spaceId, tabId, null);
        foreach (var restored in restoredWindows.Values.ToArray())
        {
            if (restored.Selections.GetValueOrDefault(spaceId) != tabId) continue;
            var selections = new Dictionary<SpaceId, TabId?>(restored.Selections) { [spaceId] = null };
            restoredWindows[restored.Id] = restored with { Selections = selections };
        }
        tab.Place(TabPlacement.Current, null, clock.Now); tab.SetSplit(null); tab.Activate(clock.Now);
        target.AddOpenedTab(tab, window.Selection(spaceId)); window.Select(spaceId, tabId);
    }
    public void Visit(SpaceId spaceId, TabId tabId) => Space(spaceId).RecordVisit(Space(spaceId).Tab(tabId), clock.Now, ids);
    public void RenameTab(SpaceId spaceId, TabId tabId, string? title) => Space(spaceId).Tab(tabId).Rename(title, clock.Now);
    public void PlaceTab(SpaceId spaceId, TabId tabId, TabPlacement placement, FolderId? folder)
        => Space(spaceId).Place(tabId, placement, folder, clock.Now);
    public WorkspaceState Capture()
    {
        var selections = spaces.Select(s => s.Capture(windows.FirstOrDefault(w => w.SpaceId == s.Id) is { } window
            ? window.Selection(s.Id) : s.RestoredSelection)).ToArray();
        var active = windows.Select(w => new WindowState(w.Id, w.SpaceId, new Dictionary<SpaceId, TabId?>(w.Selections), w.PlatformSceneId)).ToArray();
        return new(Id, DefaultSpaceId, windows.FirstOrDefault()?.SpaceId ?? RestoredSpaceId ?? DefaultSpaceId,
            selections, active.Concat(restoredWindows.Values).ToArray(), deletions.ToArray());
    }
    public static BrowserWorkspace Restore(WorkspaceState state, IIdSource ids, IClock clock, bool allowsInternalPages = false)
    {
        var workspace = new BrowserWorkspace(state.Id, ids, clock, allowsInternalPages);
        var spaceIds = new HashSet<SpaceId>(); var profileIds = new HashSet<ProfileId>(); var tabIds = new HashSet<TabId>();
        // Reject ambiguous identities before publishing any aggregate. The source remains intact for repair.
        var tombstones = (state.SpaceDeletions ?? []).ToArray();
        if (tombstones.Select(d => d.Space).Distinct().Count() != tombstones.Length
            || tombstones.Select(d => d.Profile).Distinct().Count() != tombstones.Length)
            throw new BrowserRuleException("duplicate_deletion_identity");
        foreach (var space in state.Spaces.Where(s => !tombstones.Any(d => d.Completed && (d.Space == s.Id || d.Profile == s.ProfileId))))
        {
            if (!spaceIds.Add(space.Id) || !profileIds.Add(space.ProfileId)
                || space.Tabs.Any(t => !tabIds.Add(t.Id)) || space.Archive.Any(a => !tabIds.Add(a.Tab.Id)))
                throw new BrowserRuleException("duplicate_persisted_identity");
            workspace.spaces.Add(BrowserSpace.Restore(space));
        }
        if (workspace.spaces.Count == 0) throw new BrowserRuleException("empty_session");
        workspace.DefaultSpaceId = state.DefaultSpaceId is null ? null
            : state.DefaultSpaceId is { } defaultId && spaceIds.Contains(defaultId) ? defaultId : workspace.spaces[0].Id;
        workspace.RestoredSpaceId = state.SelectedSpaceId is { } selectedId && spaceIds.Contains(selectedId)
            ? selectedId : workspace.DefaultSpaceId ?? workspace.spaces[0].Id;
        var sceneIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var window in state.Windows)
        {
            if (workspace.restoredWindows.ContainsKey(window.Id)) throw new BrowserRuleException("duplicate_persisted_identity");
            if (window.PlatformSceneId is { } scene && (scene.Length is 0 or > 512 || !sceneIds.Add(scene)))
                throw new BrowserRuleException("invalid_scene_id");
            var selected = spaceIds.Contains(window.SpaceId) ? window.SpaceId : workspace.RestoredSpaceId!.Value;
            var selections = window.Selections.Where(s => spaceIds.Contains(s.Key)).ToDictionary(s => s.Key,
                s => s.Value is { } tab && workspace.Space(s.Key).Tabs.Any(t => t.Id == tab) ? s.Value : null);
            workspace.restoredWindows.Add(window.Id, new(window.Id, selected, selections, window.PlatformSceneId));
        }
        foreach (var deletion in tombstones)
        {
            if (!deletion.Completed)
            {
                var space = workspace.Space(deletion.Space);
                if (space.ProfileId != deletion.Profile) throw new BrowserRuleException("stale_space_deletion");
                space.BeginDeletion();
            }
            workspace.deletions.Add(deletion);
        }
        var survivor = workspace.spaces.FirstOrDefault(s => !s.IsDeleting)
            ?? throw new BrowserRuleException("empty_session");
        foreach (var deletion in tombstones) workspace.RemoveSpaceSelections(deletion.Space, survivor.Id);
        return workspace;
    }
    public static void ValidateUrl(string? url, bool allowsInternalPages = false)
    {
        if (url is null || url.Length > 16384 || !Uri.TryCreate(url, UriKind.Absolute, out var parsed)
            || (parsed.Scheme is not ("http" or "https") && url != "about:blank"
                && !(allowsInternalPages && parsed.Scheme is "chrome" or "crest" && parsed.Host.Length > 0)
                && !(allowsInternalPages && parsed.Scheme == "chrome-extension" && parsed.Host.Length == 32
                    && parsed.Host.All(c => c is >= 'a' and <= 'p')))
            || !string.IsNullOrEmpty(parsed.UserInfo))
            throw new BrowserRuleException("unsupported_url");
    }
}
