using CrestCore.Contracts;

namespace CrestCore.Application;

/// Which filter lists the device subscribes to, beyond those it has on by
/// default, and the sites where a Space blocks nothing. The device store keeps
/// the person's list choices and the persistent session's Spaces' sites; any
/// other Space's sites, such as a private one's, live as long as the process.
/// The Spaces of a Sub-Space group share their sites, as they share their
/// site permissions.
internal sealed partial class Device {
    #region Types

    /// What the person chose for filtering on this device: the catalog lists
    /// turned on or off, the lists added by address, and their own filters.
    internal sealed record FilterPreferences(IReadOnlyDictionary<FilterList, bool> Choices,
        IReadOnlyList<CustomFilterList> CustomLists, string CustomFilters);

    #endregion

    #region Variables

    /// The most filter lists the person may add.
    public const int MaximumCustomFilterLists = 30;

    /// The longest the person's own filters may be.
    public const int MaximumCustomFiltersBytes = 512 * 1024;

    /// The lists the person turned on or off; any other follows its default.
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
            lock (gate) return new(new Dictionary<FilterList, bool>(filterListChoices), [.. customFilterLists], customFilters);
        }
    }

    /// Every site where a Space blocks nothing.
    internal IReadOnlyList<SiteContentBlocking> BlockingSites {
        get {
            lock (gate) return [.. keptBlockingSites, .. passingBlockingSites];
        }
    }

    #endregion

    #region Actions - Filter lists

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

    /// Blocks, or stops blocking, ads and trackers on `origin` in `spaceId`:
    /// kept by the device store for a Space of the persistent session, and for
    /// the process alone for any other. Refused for an origin that is not valid
    /// or a locked Space.
    internal void SetBlocking(Guid spaceId, SiteOrigin origin, bool blocks, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(origin);
        ArgumentNullException.ThrowIfNull(changes);
        if (!origin.IsValid) throw new Rejected(new InvalidSiteOrigin(origin));
        var (keeps, locked) = ChoiceScope(spaceId);
        if (locked) throw new Rejected(new SpaceLocked(spaceId));
        var group = PermissionGroups()(spaceId);
        var site = new SiteContentBlocking(spaceId, origin);
        lock (gate) {
            var sites = keeps ? keptBlockingSites : passingBlockingSites;
            bool changed = blocks
                ? sites.RemoveAll(kept => kept.Origin == origin && group.Contains(kept.SpaceId)) > 0
                : !sites.Any(kept => kept.Origin == origin && group.Contains(kept.SpaceId));
            if (!changed) return;
            if (!blocks) sites.Add(site);
            if (keeps) storage?.EnqueueDevice(Records());
            changes.Publish(new SiteContentBlockingChanged([.. keptBlockingSites, .. passingBlockingSites]));
        }
    }

    /// Forgets the sites of a deleted Space.
    public void ForgetBlockingSites(Guid spaceId, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        lock (gate) {
            int removed = keptBlockingSites.RemoveAll(site => site.SpaceId == spaceId);
            removed += passingBlockingSites.RemoveAll(site => site.SpaceId == spaceId);
            if (removed == 0) return;
            storage?.EnqueueDevice(Records());
            changes.Publish(new SiteContentBlockingChanged([.. keptBlockingSites, .. passingBlockingSites]));
        }
    }

    /// Whether a page of `spaceId` showing `origin` blocks ads and trackers:
    /// its Space's policy blocks, and the Space did not turn blocking off for
    /// the site. A Space no attached session holds blocks nothing. Called
    /// without the device lock, since it reads the sessions.
    internal bool Blocks(Guid spaceId, SiteOrigin? origin) {
        KeyValuePair<Guid, NativeSessionAuthority>[] attached;
        lock (gate) attached = [.. workspaces];
        var policy = attached.Select(entry => entry.Value.Current.Space(spaceId)).FirstOrDefault(space => space is not null)
            ?.Settings.BrowsingPreferences.ContentBlocking;
        if (policy?.BlocksContent != true) return false;
        if (origin is null) return true;
        var group = PermissionGroups()(spaceId);
        lock (gate)
            return !keptBlockingSites.Concat(passingBlockingSites)
                .Any(site => site.Origin == origin && group.Contains(site.SpaceId));
    }

    /// Takes the device store's choices and sites at launch.
    private void RestoreContentBlocking(DeviceRecords records) {
        foreach (var (list, isOn) in records.FilterListChoices) filterListChoices[list] = isOn;
        customFilterLists.AddRange(records.CustomFilterLists.DistinctBy(list => list.Id));
        customFilters = records.CustomFilters;
        keptBlockingSites.AddRange(records.BlockingSites.Distinct());
    }

    #endregion
}
