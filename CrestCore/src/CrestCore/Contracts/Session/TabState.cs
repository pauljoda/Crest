using CrestCore.Domain;

namespace CrestCore.Contracts;

/// <summary>
/// A tab as its Space keeps it. A native view has <see cref="NativeContent"/> and no
/// <see cref="Url"/>; a Start Page has neither. <see cref="StoredIconMode"/> is null
/// for a tab that never chose how its icon is filled, which then follows its
/// <see cref="Symbol"/>. Favicon bytes, live pages and engine history are never part of it.
/// The core publishes the values it resolves from these fields beside them, so no
/// platform works them out again, and never stores them. <see cref="SavedTitle"/>,
/// <see cref="SavedFaviconUrl"/> and <see cref="SavedIconAccent"/> are the title,
/// favicon address and icon color of the page at <see cref="SavedUrl"/>, kept as the
/// tab leaves that page, which a tab that returns there shows again; a tab written
/// before they were kept has none until it next leaves its saved address.
/// </summary>
[Observed]
public sealed record TabState(
    Guid Id,
    string Title,
    string? Url,
    NativeTabContent? NativeContent,
    string? SavedUrl,
    string Symbol,
    string? FaviconUrl,
    TabIconAccent? IconAccent,
    TabIconMode? StoredIconMode,
    TabPlacement Placement,
    Guid? FolderId,
    Guid? SplitGroupId,
    DateTimeOffset LastActivatedAt,
    DateTimeOffset? PositionModifiedAt,
    string? CustomTitle,
    DateTimeOffset? TitleModifiedAt,
    bool KeepsPageLoaded,
    string? SavedTitle = null,
    string? SavedFaviconUrl = null,
    TabIconAccent? SavedIconAccent = null) {
    #region Variables

    /// <summary>How the tab's icon is filled: its stored mode, or for a tab written
    /// before modes were stored, or with a term this build cannot name, the one its
    /// symbol implies.</summary>
    [Resolved]
    public TabIconMode IconMode => StoredIconMode ?? TabIconMode.Inferred(Symbol);

    /// <summary>The name every tab surface shows: the person's rename, or the page's
    /// title when there is none. A blank rename, however it arrived, is none.</summary>
    [Resolved]
    public string DisplayTitle => string.IsNullOrWhiteSpace(CustomTitle) ? Title : CustomTitle.Trim();

    /// <summary>A saved or pinned tab shows a page other than the one it was saved at.
    /// A current tab belongs nowhere, so it is never away.</summary>
    [Resolved]
    public bool IsAwayFromSavedAddress => SavedAddress is { } saved && Url is { } url
        && !new WebAddress(url).IsSamePage(new WebAddress(saved));

    /// <summary>Whether returning to its saved address puts the saved page's image back
    /// on the tab: it shows another page, and its icon follows its page.</summary>
    internal bool ReturnRestoresImage => IsAwayFromSavedAddress && IconMode.FollowsPage;

    /// <summary>Whether the favicon the tab wears was taken from the page at its saved
    /// address, rather than one it showed before that page's own icon arrived.</summary>
    internal bool WearsSavedPageIcon => SavedUrl is { } saved && FaviconUrl is { } icon
        && new WebAddress(icon).IsSamePage(new WebAddress(saved));

    /// <summary>The icon follows the page, and the favicon the tab keeps was taken from
    /// the page it shows, so the page need not fetch it again once the platform holds
    /// the image.</summary>
    [Resolved]
    public bool PageIconIsCurrent => IconMode.FollowsPage && FaviconUrl is { } icon && Url is { } url
        && new WebAddress(icon).IsSamePage(new WebAddress(url));

    /// <summary>The address a saved or pinned tab belongs to: the one it was saved at,
    /// or the one it shows when it has none. A current tab has none.</summary>
    public string? SavedAddress => Placement.IsDurable ? SavedUrl ?? Url : null;

    /// <summary>What the tab's surface shows: the Start Page, its native view or its web
    /// page.</summary>
    [Resolved]
    public TabSurface Surface => TabSurface.Of(NativeContent, Url);

    /// <summary>The native view the tab shows, or null for a web page, a Start Page or a
    /// view another build added, which keeps its kind but has no member here.</summary>
    [Resolved]
    public NativeView? NativeView => NativeView.Named(NativeContent?.Kind);

    /// <summary>The tab is a Start Page: it shows neither a web page nor a native view,
    /// and no sidebar lists it.</summary>
    public bool IsStartPage => Surface == TabSurface.StartPage;

    /// The tab is one of its Space's pinned tabs.
    internal bool IsPinned => Placement == TabPlacement.Pinned;

    #endregion

    #region Actions - Saved address

    /// <summary>The tab belonging to <paramref name="savedUrl"/>: one newly saved at the
    /// page it shows keeps that page's title and favicon as the saved page's, one whose
    /// saved address stays keeps what it has, and one that belongs nowhere keeps
    /// none.</summary>
    internal TabState SavedAt(string? savedUrl) {
        if (savedUrl is null) return this with { SavedUrl = null, SavedTitle = null, SavedFaviconUrl = null, SavedIconAccent = null };
        if (savedUrl == SavedUrl) return this;
        var showsIt = Url is { } url && new WebAddress(url).IsSamePage(new WebAddress(savedUrl));
        // A favicon from the page shown before this one is not the saved page's.
        var wearsItsIcon = showsIt && FaviconUrl is { } icon && new WebAddress(icon).IsSamePage(new WebAddress(savedUrl));
        return this with {
            SavedUrl = savedUrl,
            SavedTitle = showsIt ? Title : null,
            SavedFaviconUrl = wearsItsIcon ? FaviconUrl : null,
            SavedIconAccent = wearsItsIcon ? IconAccent : null
        };
    }

    /// <summary>Whether showing <paramref name="url"/> takes the saved or pinned tab
    /// away from the page at its saved address.</summary>
    internal bool LeavesSavedAddress(string url) => Placement.IsDurable && SavedUrl is { } saved && Url is not null
        && !IsAwayFromSavedAddress && !new WebAddress(url).IsSamePage(new WebAddress(saved));

    /// <summary>The tab keeping the title of the page it shows as its saved page's, as
    /// it leaves that page, and its favicon address and icon color when that page's
    /// own icon had arrived; otherwise the ones kept before stay.</summary>
    internal TabState KeepingSavedAppearance() => WearsSavedPageIcon
        ? this with { SavedTitle = Title, SavedFaviconUrl = FaviconUrl, SavedIconAccent = IconAccent }
        : this with { SavedTitle = Title };

    /// <summary>The tab back at its saved address. One that showed another page wears
    /// the saved page's title where it knows it, and, when its icon follows its page,
    /// that page's favicon address and color, or none, so its row never names the page
    /// it left. A rename stays, as it is the person's.</summary>
    internal TabState ReturnedTo(string savedUrl) {
        if (!IsAwayFromSavedAddress) return this with { Url = savedUrl };
        var returned = this with { Url = savedUrl, Title = SavedTitle ?? Title };
        return ReturnRestoresImage && SavedFaviconUrl != FaviconUrl
            ? returned with { FaviconUrl = SavedFaviconUrl, IconAccent = SavedIconAccent } : returned;
    }

    #endregion

    #region Actions - Repair

    /// A new Start Page tab, last shown `now`.
    internal static TabState NewStartPage(Guid id, DateTimeOffset now) => new(id, TabKind.StartPage.Name, null, null, null,
        TabKind.StartPage.Symbol, null, null, null, TabPlacement.Current, null, null, now, null, null, null, false);

    /// The tab as repair keeps it: a blank rename is no rename, edit clocks
    /// are whole milliseconds, and a Start Page wears its own title and symbol.
    internal TabState Normalized() {
        var normalized = this with {
            CustomTitle = string.IsNullOrWhiteSpace(CustomTitle) ? null : CustomTitle.Trim(),
            PositionModifiedAt = PositionModifiedAt is { } position ? BrowserEditTimestamp.Normalize(position) : null,
            TitleModifiedAt = TitleModifiedAt is { } title ? BrowserEditTimestamp.Normalize(title) : null
        };
        return normalized.IsStartPage
            ? normalized with { Title = TabKind.StartPage.Name, Symbol = TabKind.StartPage.Symbol } : normalized;
    }

    #endregion
}
