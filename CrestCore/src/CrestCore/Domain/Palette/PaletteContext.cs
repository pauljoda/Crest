using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Everything one answer of a window's palette reads, captured once: the
/// Space the window shows and the tab it shows there, whether the window is
/// private and its default engine opens internal pages, the device's palette
/// preferences and search catalog, what the Space searches with and whether
/// it suggests searches, what the Space's palette remembers, the workspace's
/// other Spaces, and the time. Each kind of result reads it to find its rows,
/// and each signal to score them. It reads only immutable records, so a
/// palette answers without holding the core's lock.
internal sealed class PaletteContext {
    #region Variables

    /// The Space the palette speaks for, or null when the window shows none
    /// the palette may read, as a locked one.
    public SpaceState? Space { get; }

    /// The tab the window shows, which the palette leaves out.
    public Guid? ShownTabId { get; }

    public bool IsPrivate { get; }
    public bool AllowsInternalPages { get; }
    public PalettePreferences Preferences { get; }
    public SearchCatalog Catalog { get; }

    /// What the Space searches with.
    public SearchProvider Search { get; }

    /// Whether the Space suggests searches as a person types.
    public bool Suggests { get; }

    public PaletteMemory Memory { get; }

    /// The workspace's other Spaces the palette may offer.
    public IReadOnlyList<SpaceState> Spaces { get; }

    public DateTimeOffset Now { get; }

    /// The Space's history by address, or null without a Space.
    public AddressIndex? History { get; }

    /// The Space's tabs by the site each shows, gathered the first time a row
    /// asks for the tabs whose icon it may wear.
    private ILookup<string, (Guid Id, string Page)> TabsBySite => tabsBySite ??= GatherTabsBySite();
    private ILookup<string, (Guid Id, string Page)>? tabsBySite;

    #endregion

    #region Constructors

    public PaletteContext(SpaceState? space, Guid? shownTabId, bool isPrivate, bool allowsInternalPages, PalettePreferences preferences,
        SearchCatalog catalog, PaletteMemory memory, IReadOnlyList<SpaceState> spaces, DateTimeOffset now) {
        Space = space;
        ShownTabId = shownTabId;
        IsPrivate = isPrivate;
        AllowsInternalPages = allowsInternalPages;
        Preferences = preferences;
        Catalog = catalog;
        Search = space is null ? catalog.DefaultFor(isPrivate) : catalog.For(space.Settings.BrowsingPreferences, isPrivate);
        Suggests = space is not null && catalog.SuggestsFor(space.Settings.BrowsingPreferences);
        Memory = memory;
        Spaces = spaces;
        Now = now;
        History = space is null ? null : AddressIndex.Of(space.History);
    }

    #endregion

    #region Actions - Evidence

    /// What ranking reads of a place whose row `row` shows `title` at `url`,
    /// for `query`: how well the text matches it, or the page's own
    /// `pageTitle` behind a name the person gave its tab, and whether it
    /// starts the title or the address, or for an open or kept tab a name it
    /// goes by: the site name its title ends with, or its page's own title;
    /// how much the page was used, when its tab was, whether it is open or
    /// kept, and what earlier picks add. Null when the text matches neither;
    /// with nothing typed, as when the person narrowed the palette to a kind,
    /// every place matches with no text points.
    public PaletteEvidence? Evidence(PaletteQuery query, PaletteRow row, string title, string? url, DateTimeOffset? lastUsed = null,
        bool isOpen = false, bool isKept = false, HistoryEntryState? entry = null, string? pageTitle = null) {
        string address = url is null ? "" : PaletteMemory.Place(url) ?? "";
        bool prefixesTitle = query.Prefixes(title);
        bool prefixes = prefixesTitle || address.Length > 0 && query.Prefixes(address);
        int? score = query.IsEmpty ? 0 : query.Score(title, address);
        if (!query.IsEmpty && pageTitle is not null && query.Score(pageTitle, address) is { } page) score = Math.Max(score ?? 0, page);
        if (prefixes) score = Math.Max(score ?? 0, TextMatch.TextStart.Points);
        if (score is not { } matched) return null;
        bool prefixesName = (isOpen || isKept)
            && (query.PrefixesSiteName(title) || pageTitle is not null && (query.Prefixes(pageTitle) || query.PrefixesSiteName(pageTitle)));
        entry ??= url is not null && new WebAddress(url).Normalized is { } normalized ? History?.Entry(normalized) : null;
        double frecency = url is null ? 0 : Memory.Frecency(url, entry, Now);
        return new(matched, prefixes, prefixesTitle, prefixesName, frecency, lastUsed, isOpen, isKept, Learned(query, row));
    }

    /// What ranking reads of a row that matched with `score` and is no
    /// place: only the match and what earlier picks add.
    public PaletteEvidence Matched(PaletteQuery query, PaletteRow row, int score) =>
        new(score, Prefixes: false, PrefixesTitle: query.Prefixes(row.Title), PrefixesName: false, Frecency: 0, LastUsed: null,
            IsOpen: false, IsKept: false, Learned(query, row));

    /// What the person's earlier picks for what was typed add to `row`.
    public double Learned(PaletteQuery query, PaletteRow row) =>
        Preferences.LearnsChoices && Destination(row) is { } destination ? Memory.Learned(query.Text, destination, Now) : 0;

    /// Where `row` leads, as picks remember it.
    public PaletteDestination? Destination(PaletteRow row) =>
        row.Kind.Destination(row, tab => Space?.Tabs.FirstOrDefault(candidate => candidate.Id == tab) is { } found
            ? found.SavedAddress ?? found.Url : null);

    #endregion

    #region Actions - Icons

    /// The tabs whose icon a row that opens `url` may wear, best first: the
    /// Space's tabs showing the same page, whatever their fragment, then the
    /// others on the same site, its host in lower case without `www.` with
    /// its port; among each, open tabs and the pins the Space shows before
    /// archived tabs. None for an address that names no web page.
    public IReadOnlyList<Guid> IconTabs(string url) {
        if (new WebAddress(url).Normalized is not { } page || Site(url) is not { } site) return [];
        var tabs = TabsBySite[site];
        return [.. tabs.Where(tab => tab.Page == page).Concat(tabs.Where(tab => tab.Page != page)).Select(tab => tab.Id)];
    }

    /// Every tab of the Space that shows a web page, open tabs and shown pins
    /// first, then archived tabs, by site.
    private ILookup<string, (Guid Id, string Page)> GatherTabsBySite() {
        List<(string Site, Guid Id, string Page)> found = [];
        if (Space is { } space)
            foreach (var tab in space.Tabs.Concat(space.ArchivedTabs.Select(archived => archived.Tab)))
                if (tab.Url is { } url && new WebAddress(url).Normalized is { } page && Site(url) is { } site) found.Add((site, tab.Id, page));
        return found.ToLookup(entry => entry.Site, entry => (entry.Id, entry.Page));
    }

    /// The site `url` names, as rows match tabs by: its host in lower case
    /// without `www.`, with its port when it is not the scheme's own.
    private static string? Site(string url) {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var parsed) || parsed.Host.Length == 0) return null;
        string host = PaletteMemory.WithoutWww(parsed.Host.ToLowerInvariant());
        return parsed.IsDefaultPort ? host : $"{host}:{parsed.Port}";
    }

    #endregion

    #region Actions - Support

    /// The host `url` names, or null for none.
    public static string? Host(string? url) =>
        url is not null && Uri.TryCreate(url, UriKind.Absolute, out var parsed) && parsed.Host.Length > 0 ? parsed.Host : null;

    #endregion
}

/// What ranking reads of one row: how well the text matched it, whether the
/// text starts its title or address, whether it starts another name an open
/// or kept tab goes by (the site name its title ends with, or its page's own
/// title behind a name the person gave it), how much its page was used, when
/// its tab was last used, whether it is open or kept, and what the person's
/// earlier picks for the same text add.
internal sealed record PaletteEvidence(int Match, bool Prefixes, bool PrefixesTitle, bool PrefixesName, double Frecency,
    DateTimeOffset? LastUsed, bool IsOpen, bool IsKept, double Learned);
