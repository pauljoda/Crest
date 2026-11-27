using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// Ad blocking state for this device: the chosen level, per-list overrides,
/// custom lists, user filters, and sites where blocking is turned off. Not
/// thread-safe: the device lock guards it.
internal sealed class ContentBlockingLedger {
    #region Static Variables

    /// The most filter lists the person may add.
    public const int MaximumCustomFilterLists = 30;
    /// The longest address a custom filter list may have.
    public const int MaximumFilterListAddressLength = 2_048;
    /// The longest the person's own filters may be.
    public const int MaximumCustomFiltersBytes = 512 * 1024;

    #endregion

    #region Variables

    private ContentBlockingLevel? level;
    private readonly Dictionary<FilterList, bool> filterListChoices = [];
    private readonly List<CustomFilterList> customFilterLists = [];
    private string customFilters = "";
    private readonly List<SiteContentBlocking> keptBlockingSites = [];
    private readonly List<SiteContentBlocking> passingBlockingSites = [];

    /// The explicitly chosen or adopted level, or null before either.
    public ContentBlockingLevel? Level => level;

    /// The catalog lists the person explicitly turned on or off.
    public IReadOnlyDictionary<FilterList, bool> FilterListChoices => new Dictionary<FilterList, bool>(filterListChoices);

    /// The custom filter lists in the order added.
    public IReadOnlyList<CustomFilterList> CustomFilterLists => [.. customFilterLists];

    /// The person's own filters.
    public string CustomFilters => customFilters;

    /// Sites turned off from persistent Spaces, kept in the device store.
    public IReadOnlyList<SiteContentBlocking> PersistentBlockingSites => [.. keptBlockingSites];

    /// Every site where Crest blocks nothing.
    public IReadOnlyList<SiteContentBlocking> BlockingSites => [.. keptBlockingSites, .. passingBlockingSites];

    #endregion

    #region Actions - Restoration

    /// Takes the device store's choices and sites at launch.
    public void Restore(DeviceRecords records) {
        level = records.ContentBlockingLevel;
        filterListChoices.Clear();
        foreach (var (list, isOn) in records.FilterListChoices) filterListChoices[list] = isOn;
        customFilterLists.Clear();
        customFilterLists.AddRange(records.CustomFilterLists.DistinctBy(list => list.Id));
        customFilters = records.CustomFilters;
        keptBlockingSites.Clear();
        keptBlockingSites.AddRange(records.BlockingSites.Distinct());
    }

    /// Adopts `adopted` when no level has been recorded yet. Answers whether it
    /// was recorded.
    public bool AdoptLevelIfUnset(ContentBlockingLevel adopted) {
        if (level is not null) return false;
        level = adopted;
        return true;
    }

    #endregion

    #region Actions - Filter lists

    /// Snapshot of filtering choices for `FilterLibrary`.
    public FilterPreferences Preferences(ContentBlockingLevel resolvedLevel, bool cleansCopiedLinks) =>
        new(resolvedLevel, new Dictionary<FilterList, bool>(filterListChoices), [.. customFilterLists], customFilters,
            cleansCopiedLinks);

    /// Sets the level, clearing catalog overrides when switching to a blocking
    /// level. Answers whether anything changed.
    public bool SetLevel(ContentBlockingLevel next, ContentBlockingLevel current) {
        bool resetsLists = next.BlocksContent && filterListChoices.Count > 0;
        if (next == current && !resetsLists) return false;
        level = next;
        if (next.BlocksContent) filterListChoices.Clear();
        return true;
    }

    /// Turns `list` on or off. Answers whether anything changed.
    public bool ChooseFilterList(FilterList list, bool isOn) {
        if (filterListChoices.TryGetValue(list, out bool chosen) && chosen == isOn) return false;
        filterListChoices[list] = isOn;
        return true;
    }

    /// Adds the list at `url` as `id`, on. Answers whether anything changed.
    public bool AddCustomFilterList(Guid id, string url) {
        string address = url.Trim();
        if (address.Length > MaximumFilterListAddressLength || !Uri.TryCreate(address, UriKind.Absolute, out var parsed)
            || WebScheme.Spelled(parsed.Scheme) != WebScheme.Https || string.IsNullOrEmpty(parsed.Host))
            throw new Rejected(new FilterListAddressInvalid(url));
        if (customFilterLists.Any(list => list.Id == id || list.Url == parsed.AbsoluteUri)) return false;
        if (customFilterLists.Count >= MaximumCustomFilterLists)
            throw new Rejected(new CustomFilterListLimitReached(MaximumCustomFilterLists));
        customFilterLists.Add(new(id, parsed.AbsoluteUri, IsOn: true));
        return true;
    }

    /// Removes the custom list `id`. Answers whether it was present.
    public bool RemoveCustomFilterList(Guid id) => customFilterLists.RemoveAll(list => list.Id == id) > 0;

    /// Turns the custom list `id` on or off. Answers whether anything changed.
    public bool ChooseCustomFilterList(Guid id, bool isOn) {
        int index = customFilterLists.FindIndex(list => list.Id == id);
        if (index < 0 || customFilterLists[index].IsOn == isOn) return false;
        customFilterLists[index] = customFilterLists[index] with { IsOn = isOn };
        return true;
    }

    /// Replaces the person's own filters. Answers whether anything changed.
    public bool SetCustomFilters(string text) {
        if (Encoding.UTF8.GetByteCount(text) > MaximumCustomFiltersBytes)
            throw new Rejected(new CustomFiltersTooLarge(MaximumCustomFiltersBytes));
        if (customFilters == text) return false;
        customFilters = text;
        return true;
    }

    /// Removes the lines of the person's filters that `matches`. Answers
    /// whether any went.
    public bool RemoveCustomFilters(Func<string, bool> matches) {
        var lines = customFilters.Split('\n');
        var kept = lines.Where(line => !matches(line)).ToArray();
        if (kept.Length == lines.Length) return false;
        customFilters = string.Join('\n', kept);
        return true;
    }

    /// Whether a line of the person's filters `matches`.
    public bool HoldsCustomFilter(Func<string, bool> matches) => customFilters.Split('\n').Any(matches);

    /// Adds `rule` as its own line of the person's filters unless present.
    public bool AddCustomFilter(string rule) {
        if (customFilters.Split('\n').Any(line => line.Trim() == rule)) return false;
        var text = customFilters.Length == 0 || customFilters.EndsWith('\n')
            ? customFilters + rule
            : customFilters + "\n" + rule;
        if (Encoding.UTF8.GetByteCount(text) > MaximumCustomFiltersBytes)
            throw new Rejected(new CustomFiltersTooLarge(MaximumCustomFiltersBytes));
        customFilters = text;
        return true;
    }

    #endregion

    #region Actions - Sites

    /// Blocks or unblocks ads on `origin`, recording whether the visible list
    /// changed and whether the persistent store changed.
    public (bool Changed, bool StoresChange) SetBlocking(Guid spaceId, SiteOrigin origin, bool blocks, bool keeps) {
        if (blocks) {
            bool storesChange = keptBlockingSites.RemoveAll(site => site.Origin == origin) > 0;
            bool passingChanged = passingBlockingSites.RemoveAll(site => site.Origin == origin) > 0;
            return (storesChange || passingChanged, storesChange);
        }
        if (keptBlockingSites.Any(site => site.Origin == origin)) return (false, false);
        bool passing = passingBlockingSites.Any(site => site.Origin == origin);
        if (passing && !keeps) return (false, false);
        passingBlockingSites.RemoveAll(site => site.Origin == origin);
        (keeps ? keptBlockingSites : passingBlockingSites).Add(new(spaceId, origin));
        return (true, keeps);
    }

    /// Forgets memory-only site overrides recorded for `spaceId`.
    public bool ForgetPassingSites(Guid spaceId) => passingBlockingSites.RemoveAll(site => site.SpaceId == spaceId) > 0;

    /// Whether `origin` is exempted from blocking.
    public bool IsExempt(SiteOrigin origin) =>
        keptBlockingSites.Concat(passingBlockingSites).Any(site => site.Origin == origin);

    #endregion
}
