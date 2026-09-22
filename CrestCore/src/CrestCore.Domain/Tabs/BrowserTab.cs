namespace CrestCore.Domain;

public sealed class BrowserTab(Guid id, TabContent content, string? url, Guid? pageId) {
    #region Variables

    public Guid Id { get; } = id;
    public TabContent Content { get; private set; } = ValidContent(content, url, pageId);
    public Guid? PageId { get; private set; } = pageId;
    public ulong Generation { get; private set; } = pageId is null ? 0UL : 1UL;
    public string? Url { get; private set; } = url;
    public string Title { get; private set; } = content.Title(url);
    public TabPhase Phase { get; private set; } = !content.IsWebPage ? TabPhase.Ready : pageId is null ? TabPhase.Dormant : TabPhase.Creating;
    public TabPlacement Placement { get; private set; }
    public Guid? FolderId { get; private set; }
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

    #endregion

    #region Actions - Validation

    private static TabContent ValidContent(TabContent content, string? url, Guid? pageId) {
        if (content is null || content.IsWebPage != (url is not null) || !content.IsWebPage && pageId is not null)
            throw new BrowserRuleException(BrowserRuleCodes.InvalidTabContent);
        return content;
    }

    #endregion

    #region Actions - Persistence

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

    #endregion

    #region Actions - Page lifecycle

    public void Activate(DateTimeOffset now) => LastActivatedAt = now;

    public void CreatePage(Guid? page, bool allowsInternalPages = false) {
        if (!Content.IsWebPage || Phase is not (TabPhase.Dormant or TabPhase.Failed))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidTransition);
        BrowserSpace.ValidateUrl(Url, allowsInternalPages);
        PageId = page; Generation++; Phase = TabPhase.Creating; Failure = null;
    }

    public void NavigateStartPage(string url, Guid? page, bool allowsInternalPages = false) {
        if (!Content.IsStartPage || Placement != TabPlacement.Current)
            throw new BrowserRuleException(BrowserRuleCodes.NotStartPageDraft);
        BrowserSpace.ValidateUrl(url, allowsInternalPages);
        Content = TabContent.Web; Url = url; Title = Content.Title(url);
        Phase = TabPhase.Dormant;
        CreatePage(page, allowsInternalPages);
    }

    public void Created() {
        if (Phase != TabPhase.Creating) throw new BrowserRuleException(BrowserRuleCodes.InvalidTransition);
        Phase = TabPhase.Ready;
    }

    public void Observe(string? url, string title, bool loading, bool back, bool forward, string? failure) {
        if (Phase == TabPhase.Creating) throw new BrowserRuleException(BrowserRuleCodes.PageNotReady);
        if (url is not null) Url = url;
        Title = title; IsLoading = loading; CanGoBack = back; CanGoForward = forward; Failure = failure;
    }

    public void RequestClose() {
        if (Phase == TabPhase.Closing) throw new BrowserRuleException(BrowserRuleCodes.AlreadyClosing);
        Phase = TabPhase.Closing;
    }

    public void RequestUnload() {
        if (!Content.IsWebPage || Phase != TabPhase.Ready || KeepsPageLoaded || IsLoading)
            throw new BrowserRuleException(BrowserRuleCodes.PageNotUnloadable);
        Phase = TabPhase.Unloading;
    }

    public void CancelUnload() {
        if (Phase != TabPhase.Unloading) throw new BrowserRuleException(BrowserRuleCodes.InvalidTransition);
        Phase = TabPhase.Ready;
    }

    public void CancelClose() { Phase = TabPhase.Ready; }

    public void Unload(bool returnToSavedUrl = false) {
        PageId = null; IsLoading = false; CanGoBack = false; CanGoForward = false; Failure = null;
        Phase = Content.IsWebPage ? TabPhase.Dormant : TabPhase.Ready;
        if (returnToSavedUrl && SavedUrl is not null) Url = SavedUrl;
    }

    public void Fail(string reason) { Phase = TabPhase.Failed; Failure = reason; IsLoading = false; }

    #endregion

    #region Actions - Saved location

    /// The address a saved or pinned tab belongs to. A current tab has none:
    /// it is wherever browsing took it, which is why it cannot be "away".
    public string? SavedSiteUrl => SavedUrl ?? (Placement == TabPlacement.Current ? null : Url);

    public bool SupportsSavedLocationEditing => Placement != TabPlacement.Current && SavedSiteUrl is not null;

    public bool IsAwayFromSavedLocation
        => SupportsSavedLocationEditing && Url is not null && !HistoryPolicy.SamePage(Url, SavedSiteUrl);

    #endregion

    #region Mutators

    /// A page reporting where it landed and what it is called. Unlike
    /// <see cref="Observe"/> this carries no transport state, so a background
    /// Split View card can record its own page without claiming the focused
    /// tab's loading, history or failure state.
    public void ObserveAppearance(string? url, string? title) {
        if (url is not null) Url = url;
        if (!string.IsNullOrEmpty(title)) Title = title;
    }

    /// Adopts the page the tab is actually showing as the one it belongs to.
    public bool ReplaceSavedLocation() {
        if (!IsAwayFromSavedLocation || Url is not { } url) return false;
        SavedUrl = url; return true;
    }

    /// Returns the tab to the address it belongs to, and reports it so the
    /// platform can navigate the live page to the same place.
    public string? RestoreSavedLocation() {
        if (!SupportsSavedLocationEditing || SavedSiteUrl is not { } saved) return null;
        Url = saved; return saved;
    }

    public void Rename(string? title, DateTimeOffset now) {
        title = title?.Trim();
        if (title?.Length > 4096) throw new BrowserRuleException(BrowserRuleCodes.InvalidTitle);
        CustomTitle = string.IsNullOrEmpty(title) ? null : title; TitleModifiedAt = BrowserEditTimestamp.Normalize(now);
    }

    public void SetResidency(bool keepLoaded) => KeepsPageLoaded = keepLoaded;

    internal void SetSplit(Guid? id) => SplitGroupId = id;

    internal void MarkPosition(DateTimeOffset now) => PositionModifiedAt = BrowserEditTimestamp.Normalize(now);

    public void Place(TabPlacement placement, Guid? folder, DateTimeOffset? now = null, bool preservesSplit = false) {
        if (Placement == placement && FolderId == folder) return;
        if (placement != TabPlacement.Current) SavedUrl ??= Url;
        if (placement == TabPlacement.Current) SavedUrl = null;
        Placement = placement; FolderId = folder;
        if (!preservesSplit) SplitGroupId = null;
        if (now is { } changedAt) MarkPosition(changedAt);
    }

    #endregion
}
