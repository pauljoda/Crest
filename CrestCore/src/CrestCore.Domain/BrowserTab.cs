namespace CrestCore.Domain;

public enum TabPhase { Dormant, Creating, Ready, Unloading, Closing, Failed }
public enum TabPlacement { Current, Pinned, Saved }

public sealed class BrowserTab(TabId id, TabContent content, string? url, PageId? pageId) {
    public TabId Id { get; } = id;
    public TabContent Content { get; private set; } = ValidContent(content, url, pageId);
    public PageId? PageId { get; private set; } = pageId;
    public ulong Generation { get; private set; } = pageId is null ? 0UL : 1UL;
    public string? Url { get; private set; } = url;
    public string Title { get; private set; } = content.Title(url);
    public TabPhase Phase { get; private set; } = !content.IsWebPage ? TabPhase.Ready : pageId is null ? TabPhase.Dormant : TabPhase.Creating;
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
    public string? NativeKind => Content.NativeKind;

    private static TabContent ValidContent(TabContent content, string? url, PageId? pageId) {
        if (content is null || content.IsWebPage != (url is not null) || !content.IsWebPage && pageId is not null)
            throw new BrowserRuleException("invalid_tab_content");
        return content;
    }

    public static BrowserTab Restore(TabState state) {
        var tab = new BrowserTab(state.Id, state.Content, state.Url, null) {
            Title = state.Title,
            Placement = state.Placement,
            FolderId = state.FolderId,
            SavedUrl = state.SavedUrl,
            CustomTitle = string.IsNullOrWhiteSpace(state.CustomTitle) ? null : state.CustomTitle.Trim(),
            LastActivatedAt = state.LastActivatedAt,
            PositionModifiedAt = state.PositionModifiedAt,
            TitleModifiedAt = state.TitleModifiedAt,
            KeepsPageLoaded = state.KeepsPageLoaded,
            SplitGroupId = state.SplitGroupId
        };
        return tab;
    }
    public TabState Capture() => new(Id, Content, Url, Title, Placement, FolderId, SavedUrl, CustomTitle,
        LastActivatedAt, PositionModifiedAt, TitleModifiedAt, KeepsPageLoaded, SplitGroupId);
    public void Activate(DateTimeOffset now) => LastActivatedAt = now;
    public void Rename(string? title, DateTimeOffset now) {
        title = title?.Trim();
        if (title?.Length > 4096) throw new BrowserRuleException("invalid_title");
        CustomTitle = string.IsNullOrEmpty(title) ? null : title; TitleModifiedAt = BrowserEditTimestamp.Normalize(now);
    }
    public void SetResidency(bool keepLoaded) => KeepsPageLoaded = keepLoaded;
    public void CreatePage(PageId page, bool allowsInternalPages = false) {
        if (!Content.IsWebPage || Phase is not (TabPhase.Dormant or TabPhase.Failed))
            throw new BrowserRuleException("invalid_transition");
        BrowserSpace.ValidateUrl(Url, allowsInternalPages);
        PageId = page; Generation++; Phase = TabPhase.Creating; Failure = null;
    }

    public void NavigateStartPage(string url, PageId page, bool allowsInternalPages = false) {
        if (!Content.IsStartPage || Placement != TabPlacement.Current)
            throw new BrowserRuleException("not_start_page_draft");
        BrowserSpace.ValidateUrl(url, allowsInternalPages);
        Content = TabContent.Web; Url = url; Title = Content.Title(url);
        Phase = TabPhase.Dormant;
        CreatePage(page, allowsInternalPages);
    }

    public void Created() {
        if (Phase != TabPhase.Creating) throw new BrowserRuleException("invalid_transition");
        Phase = TabPhase.Ready;
    }

    public void Observe(string? url, string title, bool loading, bool back, bool forward, string? failure) {
        if (Phase == TabPhase.Creating) throw new BrowserRuleException("page_not_ready");
        if (url is not null) Url = url;
        Title = title; IsLoading = loading; CanGoBack = back; CanGoForward = forward; Failure = failure;
    }

    public void RequestClose() {
        if (Phase == TabPhase.Closing) throw new BrowserRuleException("already_closing");
        Phase = TabPhase.Closing;
    }

    public void RequestUnload() {
        if (!Content.IsWebPage || Phase != TabPhase.Ready || KeepsPageLoaded || IsLoading)
            throw new BrowserRuleException("page_not_unloadable");
        Phase = TabPhase.Unloading;
    }
    public void CancelUnload() {
        if (Phase != TabPhase.Unloading) throw new BrowserRuleException("invalid_transition");
        Phase = TabPhase.Ready;
    }

    public void CancelClose() { Phase = TabPhase.Ready; }
    public void Unload(bool returnToSavedUrl = false) {
        PageId = null; IsLoading = false; CanGoBack = false; CanGoForward = false; Failure = null;
        Phase = Content.IsWebPage ? TabPhase.Dormant : TabPhase.Ready;
        if (returnToSavedUrl && SavedUrl is not null) Url = SavedUrl;
    }
    public void Fail(string reason) { Phase = TabPhase.Failed; Failure = reason; IsLoading = false; }
    internal void SetSplit(Guid? id) => SplitGroupId = id;
    internal void MarkPosition(DateTimeOffset now) => PositionModifiedAt = BrowserEditTimestamp.Normalize(now);
    public void Place(TabPlacement placement, FolderId? folder, DateTimeOffset? now = null, bool preservesSplit = false) {
        if (Placement == placement && FolderId == folder) return;
        if (placement != TabPlacement.Current) SavedUrl ??= Url;
        if (placement == TabPlacement.Current) SavedUrl = null;
        Placement = placement; FolderId = folder;
        if (!preservesSplit) SplitGroupId = null;
        if (now is { } changedAt) MarkPosition(changedAt);
    }
}
