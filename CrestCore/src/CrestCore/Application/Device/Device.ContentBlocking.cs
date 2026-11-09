using CrestCore.Contracts;

namespace CrestCore.Application;

/// Ad blocking on this device, which holds for every page in every Space: the
/// level it blocks at, which filter lists it subscribes to beyond those the
/// level turns on, and the sites where it blocks nothing. The device store
/// keeps the level, the person's list choices and the sites turned off from a
/// persistent Space; a site turned off from any other Space, such as a private
/// one, lasts as long as the process.
internal sealed partial class Device {
    #region Types

    /// What the person chose for filtering on this device: the level, the
    /// catalog lists turned on or off against what it turns on, the lists
    /// added by address, and their own filters.
    internal sealed record FilterPreferences(ContentBlockingLevel Level, IReadOnlyDictionary<FilterList, bool> Choices,
        IReadOnlyList<CustomFilterList> CustomLists, string CustomFilters);

    #endregion

    #region Variables

    /// The most filter lists the person may add.
    public const int MaximumCustomFilterLists = 30;

    /// The longest the person's own filters may be.
    public const int MaximumCustomFiltersBytes = 512 * 1024;

    /// The level the person chose, or the one first answered for them; null
    /// before either.
    private ContentBlockingLevel? contentBlockingLevel;
    /// The lists the person turned on or off; any other follows the level.
    private readonly Dictionary<FilterList, bool> filterListChoices = [];
    /// The lists the person added, in the order added.
    private readonly List<CustomFilterList> customFilterLists = [];
    /// The person's own filters.
    private string customFilters = "";
    /// The persistent session's Spaces' sites, which the device store keeps.
    private readonly List<SiteContentBlocking> keptBlockingSites = [];
    /// Every other Space's sites, which live as long as the process.
    private readonly List<SiteContentBlocking> passingBlockingSites = [];

    /// The lists the person turned on or off.
    internal IReadOnlyDictionary<FilterList, bool> FilterListChoices {
        get {
            lock (gate) return new Dictionary<FilterList, bool>(filterListChoices);
        }
    }

    /// What the person chose for filtering.
    internal FilterPreferences FilterChoices {
        get {
            var level = ContentBlockingLevel;
            lock (gate)
                return new(level, new Dictionary<FilterList, bool>(filterListChoices), [.. customFilterLists], customFilters);
        }
    }

    /// The level Crest blocks at. Until the person chooses one, a device whose
    /// persistent Spaces all had blocking off, from when each Space chose for
    /// itself, blocks nothing, and any other blocks at Balanced; that first
    /// answer is kept once the persistent session is attached. Called without
    /// the device lock, since it reads the session.
    internal ContentBlockingLevel ContentBlockingLevel {
        get {
            lock (gate)
                if (contentBlockingLevel is { } chosen) return chosen;
            if (Persistent() is not (_, var authority)) return ContentBlockingLevel.Balanced;
            var level = FirstLevel(authority);
            lock (gate) {
                if (contentBlockingLevel is null) {
                    contentBlockingLevel = level;
                    storage?.EnqueueDevice(Records());
                }
                return contentBlockingLevel;
            }
        }
    }

    /// Whether the persistent session, now attached, gives a device that
    /// never chose a level another level than the Balanced the core answered
    /// before it could.
    internal bool OpeningChangesContentBlockingLevel() {
        lock (gate)
            if (contentBlockingLevel is not null) return false;
        return Persistent() is (_, var authority) && FirstLevel(authority) != ContentBlockingLevel.Balanced;
    }

    /// Every site where Crest blocks nothing.
    internal IReadOnlyList<SiteContentBlocking> BlockingSites {
        get {
            lock (gate) return [.. keptBlockingSites, .. passingBlockingSites];
        }
    }

    #endregion

    #region Actions - Filter lists

    /// Blocks at `level` from now on. A level that blocks sets every catalog
    /// list to what it turns on, forgetting the lists the person turned on or
    /// off, from Off as from another level; Off blocks nothing and leaves the
    /// lists as they are. Answers whether that changed anything.
    internal bool SetContentBlockingLevel(ContentBlockingLevel level) {
        ArgumentNullException.ThrowIfNull(level);
        var current = ContentBlockingLevel;
        lock (gate) {
            bool resetsLists = level.BlocksContent && filterListChoices.Count > 0;
            if (level == current && !resetsLists) return false;
            contentBlockingLevel = level;
            if (level.BlocksContent) filterListChoices.Clear();
            storage?.EnqueueDevice(Records());
            return true;
        }
    }

    /// Turns `list` on or off for good. Answers whether that changed anything.
    internal bool ChooseFilterList(FilterList list, bool isOn) {
        ArgumentNullException.ThrowIfNull(list);
        lock (gate) {
            if (filterListChoices.TryGetValue(list, out bool chosen) && chosen == isOn) return false;
            filterListChoices[list] = isOn;
            storage?.EnqueueDevice(Records());
            return true;
        }
    }

    /// Adds the list at `url` as `id`, on. Answers whether that changed
    /// anything: adding an address already added changes nothing. Refused for
    /// an address that is not https, so no one on the network can change the
    /// list on its way, or past the most lists kept.
    internal bool AddCustomFilterList(Guid id, string url) {
        ArgumentNullException.ThrowIfNull(url);
        string address = url.Trim();
        if (address.Length > 2048 || !Uri.TryCreate(address, UriKind.Absolute, out var parsed)
            || parsed.Scheme != "https" || string.IsNullOrEmpty(parsed.Host))
            throw new Rejected(new FilterListAddressInvalid(url));
        lock (gate) {
            if (customFilterLists.Any(list => list.Id == id || list.Url == parsed.AbsoluteUri)) return false;
            if (customFilterLists.Count >= MaximumCustomFilterLists)
                throw new Rejected(new CustomFilterListLimitReached(MaximumCustomFilterLists));
            customFilterLists.Add(new(id, parsed.AbsoluteUri, IsOn: true));
            storage?.EnqueueDevice(Records());
            return true;
        }
    }

    /// Removes the list the person added as `id`. Answers whether it was there.
    internal bool RemoveCustomFilterList(Guid id) {
        lock (gate) {
            if (customFilterLists.RemoveAll(list => list.Id == id) == 0) return false;
            storage?.EnqueueDevice(Records());
            return true;
        }
    }

    /// Turns the list the person added as `id` on or off. Answers whether that
    /// changed anything.
    internal bool ChooseCustomFilterList(Guid id, bool isOn) {
        lock (gate) {
            int index = customFilterLists.FindIndex(list => list.Id == id);
            if (index < 0 || customFilterLists[index].IsOn == isOn) return false;
            customFilterLists[index] = customFilterLists[index] with { IsOn = isOn };
            storage?.EnqueueDevice(Records());
            return true;
        }
    }

    /// Replaces the person's own filters. Answers whether that changed
    /// anything. Refused for filters longer than the core keeps.
    internal bool SetCustomFilters(string text) {
        ArgumentNullException.ThrowIfNull(text);
        if (System.Text.Encoding.UTF8.GetByteCount(text) > MaximumCustomFiltersBytes)
            throw new Rejected(new CustomFiltersTooLarge(MaximumCustomFiltersBytes));
        lock (gate) {
            if (customFilters == text) return false;
            customFilters = text;
            storage?.EnqueueDevice(Records());
            return true;
        }
    }

    /// Removes the lines of the person's filters that `matches`, answering
    /// whether any went.
    internal bool RemoveCustomFilters(Func<string, bool> matches) {
        ArgumentNullException.ThrowIfNull(matches);
        lock (gate) {
            var lines = customFilters.Split('\n');
            var kept = lines.Where(line => !matches(line)).ToArray();
            if (kept.Length == lines.Length) return false;
            customFilters = string.Join('\n', kept);
            storage?.EnqueueDevice(Records());
            return true;
        }
    }

    /// Whether a line of the person's filters `matches`.
    internal bool HoldsCustomFilter(Func<string, bool> matches) {
        ArgumentNullException.ThrowIfNull(matches);
        lock (gate) return customFilters.Split('\n').Any(matches);
    }

    /// Adds `rule` as its own line of the person's filters, unless a line
    /// already holds it. Refused when the filters would grow longer than the
    /// core keeps.
    internal bool AddCustomFilter(string rule) {
        ArgumentException.ThrowIfNullOrWhiteSpace(rule);
        lock (gate) {
            if (customFilters.Split('\n').Any(line => line.Trim() == rule)) return false;
            var text = customFilters.Length == 0 || customFilters.EndsWith('\n')
                ? customFilters + rule
                : customFilters + "\n" + rule;
            if (System.Text.Encoding.UTF8.GetByteCount(text) > MaximumCustomFiltersBytes)
                throw new Rejected(new CustomFiltersTooLarge(MaximumCustomFiltersBytes));
            customFilters = text;
            storage?.EnqueueDevice(Records());
            return true;
        }
    }

    #endregion

    #region Actions - Sites

    /// Blocks, or stops blocking, ads and trackers on `origin` everywhere, from
    /// a page of `spaceId`: turning it off from a Space of the persistent
    /// session keeps the site in the device store, even one another Space
    /// turned off for the process alone, and from any other only for the
    /// process; turning it on again removes the site however it was kept,
    /// whichever Space asks. Refused for an origin that is not valid, or for
    /// turning it off from a locked Space.
    internal void SetBlocking(Guid spaceId, SiteOrigin origin, bool blocks, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(origin);
        ArgumentNullException.ThrowIfNull(changes);
        if (!origin.IsValid) throw new Rejected(new InvalidSiteOrigin(origin));
        var (keeps, locked) = ChoiceScope(spaceId);
        if (locked && !blocks) throw new Rejected(new SpaceLocked(spaceId));
        lock (gate) {
            bool storesChange;
            if (blocks) {
                storesChange = keptBlockingSites.RemoveAll(site => site.Origin == origin) > 0;
                if (passingBlockingSites.RemoveAll(site => site.Origin == origin) == 0 && !storesChange) return;
            } else {
                if (keptBlockingSites.Any(site => site.Origin == origin)) return;
                bool passing = passingBlockingSites.Any(site => site.Origin == origin);
                if (passing && !keeps) return;
                passingBlockingSites.RemoveAll(site => site.Origin == origin);
                (keeps ? keptBlockingSites : passingBlockingSites).Add(new(spaceId, origin));
                storesChange = keeps;
            }
            if (storesChange) storage?.EnqueueDevice(Records());
            changes.Publish(new SiteContentBlockingChanged([.. keptBlockingSites, .. passingBlockingSites]));
        }
    }

    /// Forgets the sites a deleted Space turned blocking off for that only the
    /// process kept. A site turned off from a persistent Space holds
    /// everywhere, so it outlives that Space.
    public void ForgetBlockingSites(Guid spaceId, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        lock (gate) {
            if (passingBlockingSites.RemoveAll(site => site.SpaceId == spaceId) == 0) return;
            changes.Publish(new SiteContentBlockingChanged([.. keptBlockingSites, .. passingBlockingSites]));
        }
    }

    /// Whether a page of `spaceId` showing `origin` blocks ads and trackers:
    /// the device blocks at a level that blocks, and blocking is not off for
    /// the site. A Space no attached session holds blocks nothing. Called
    /// without the device lock, since it reads the sessions.
    internal bool Blocks(Guid spaceId, SiteOrigin? origin) {
        if (!ContentBlockingLevel.BlocksContent) return false;
        KeyValuePair<Guid, NativeSessionAuthority>[] attached;
        lock (gate) attached = [.. workspaces];
        if (!attached.Any(entry => entry.Value.Current.Space(spaceId) is not null)) return false;
        if (origin is null) return true;
        lock (gate) return !keptBlockingSites.Concat(passingBlockingSites).Any(site => site.Origin == origin);
    }

    /// The level a device that never chose one starts at: Off when every
    /// Space of the persistent session had blocking off, and Balanced otherwise.
    private static ContentBlockingLevel FirstLevel(NativeSessionAuthority persistent) {
        var spaces = persistent.Current.Spaces;
        return spaces.Count > 0 && spaces.All(space => !space.Settings.BrowsingPreferences.ContentBlocking.BlocksContent)
            ? ContentBlockingLevel.Off
            : ContentBlockingLevel.Balanced;
    }

    /// Takes the device store's choices and sites at launch.
    private void RestoreContentBlocking(DeviceRecords records) {
        contentBlockingLevel = records.ContentBlockingLevel;
        foreach (var (list, isOn) in records.FilterListChoices) filterListChoices[list] = isOn;
        customFilterLists.AddRange(records.CustomFilterLists.DistinctBy(list => list.Id));
        customFilters = records.CustomFilters;
        keptBlockingSites.AddRange(records.BlockingSites.Distinct());
    }

    #endregion
}
