using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A tab while its Space's organization is being edited. Its durable value is
/// <see cref="State"/>; every rule below replaces that value rather than keeping a
/// second copy of any field.
public sealed class BrowserTab {
    #region Variables

    public TabState State { get; private set; }

    public Guid Id => State.Id;
    public TabContent Content => TabContent.FromStored(State.NativeContent?.Kind, State.Url, State.Title);
    public string? Url => State.Url;
    public string Title => State.Title;
    public string? CustomTitle => State.CustomTitle;
    public string? SavedUrl => State.SavedUrl;
    public TabPlacement Placement => State.Placement;
    public Guid? FolderId => State.FolderId;
    public Guid? SplitGroupId => State.SplitGroupId;
    public DateTimeOffset LastActivatedAt => State.LastActivatedAt;

    /// How the tab's icon is filled: its stored mode, or the one its symbol
    /// implies for a tab written before modes were stored.
    public TabIconMode IconMode => State.StoredIconMode ?? TabIconMode.Inferred(State.Symbol);
    public bool KeepsPageLoaded => State.KeepsPageLoaded;

    /// The address a saved or pinned tab belongs to. A current tab has none:
    /// it is wherever browsing took it, which is why it cannot be "away".
    public string? SavedSiteUrl => SavedUrl ?? (Placement.IsDurable ? Url : null);

    public bool SupportsSavedLocationEditing => Placement.IsDurable && SavedSiteUrl is not null;

    public bool IsAwayFromSavedLocation
        => SupportsSavedLocationEditing && Url is not null && !HistoryPolicy.SamePage(Url, SavedSiteUrl);

    #endregion

    #region Constructors

    private BrowserTab(TabState state) => State = state;

    #endregion

    #region Actions - Persistence

    /// A stored tab, with a blank rename read as no rename. A web page needs an
    /// address and nothing else may have one.
    public static BrowserTab Restore(TabState state) {
        var restored = state with { CustomTitle = string.IsNullOrWhiteSpace(state.CustomTitle) ? null : state.CustomTitle.Trim() };
        var content = TabContent.FromStored(restored.NativeContent?.Kind, restored.Url, restored.Title);
        if (content.IsWebPage != (restored.Url is not null)) throw new BrowserRuleException(BrowserRuleCodes.InvalidTabContent);
        return new(restored);
    }

    #endregion

    #region Actions - Activity

    public void Activate(DateTimeOffset now) => State = State with { LastActivatedAt = now };

    #endregion

    #region Actions - Pages

    /// A page reporting where it landed and what it is called. A URL entered
    /// while a native view is shown replaces that view with a web page, since
    /// persisting both is an impossible tab. A blank title is the page saying
    /// nothing rather than clearing the name.
    public void ObserveAppearance(string? url, string? title) {
        if (url is not null) State = State with { NativeContent = null, Url = url };
        if (!string.IsNullOrEmpty(title)) State = State with { Title = title };
    }

    /// A copy starts from what its source page showed, including an empty title.
    public void AdoptObservation(string? url, string title) {
        if (url is not null) State = State with { Url = url };
        State = State with { Title = title };
    }

    /// A closed saved tab reopens at the address it was saved with.
    public void ReturnToSavedUrl() {
        if (SavedUrl is { } saved) State = State with { Url = saved };
    }

    #endregion

    #region Actions - Saved location

    /// Adopts the page the tab is actually showing as the one it belongs to.
    public bool ReplaceSavedLocation() {
        if (!IsAwayFromSavedLocation || Url is not { } url) return false;
        State = State with { SavedUrl = url };
        return true;
    }

    /// Returns the tab to the address it belongs to, and reports it so the
    /// platform can navigate the live page to the same place.
    public string? RestoreSavedLocation() {
        if (!SupportsSavedLocationEditing || SavedSiteUrl is not { } saved) return null;
        State = State with { Url = saved };
        return saved;
    }

    #endregion

    #region Actions - Icon

    /// The icon slot's symbol, the address its cached favicon came from, the
    /// color behind it and the mode that chose them. Image bytes stay native.
    public void SetIcon(string symbol) => State = State with { Symbol = symbol };

    public void SetFavicon(string? url, TabIconAccent? accent) => State = State with { FaviconUrl = url, IconAccent = accent };

    public void SetIconMode(TabIconMode mode) => State = State with { StoredIconMode = mode };

    /// The page reported an icon for the document at `url`, which the tab
    /// shows. An icon that follows its page wears it, with the color the
    /// page's theme puts behind it; a chosen or pulled icon keeps what it has.
    /// Answers whether the tab wears it.
    public bool WearPageIcon(string url, TabIconAccent? accent) {
        if (!IconMode.FollowsPage) return false;
        SetIcon(TabIconMode.WebSymbol);
        SetFavicon(url, accent);
        return true;
    }

    #endregion

    #region Mutators

    public void Rename(string? title, DateTimeOffset now) {
        title = title?.Trim();
        if (title?.Length > 4096) throw new BrowserRuleException(BrowserRuleCodes.InvalidTitle);
        State = State with {
            CustomTitle = string.IsNullOrEmpty(title) ? null : title,
            TitleModifiedAt = BrowserEditTimestamp.Normalize(now)
        };
    }

    public void SetResidency(bool keepLoaded) => State = State with { KeepsPageLoaded = keepLoaded };

    internal void SetSplit(Guid? id) => State = State with { SplitGroupId = id };

    internal void MarkPosition(DateTimeOffset now) => State = State with { PositionModifiedAt = BrowserEditTimestamp.Normalize(now) };

    public void Place(TabPlacement placement, Guid? folder, DateTimeOffset? now = null, bool preservesSplit = false) {
        if (Placement == placement && FolderId == folder) return;
        var savedUrl = placement.IsDurable ? SavedUrl ?? Url : null;
        State = State with {
            SavedUrl = savedUrl,
            Placement = placement,
            FolderId = folder,
            SplitGroupId = preservesSplit ? SplitGroupId : null
        };
        if (now is { } changedAt) MarkPosition(changedAt);
    }

    #endregion
}
