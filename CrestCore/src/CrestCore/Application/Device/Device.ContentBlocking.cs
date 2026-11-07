using CrestCore.Contracts;

namespace CrestCore.Application;

/// Which filter lists the device subscribes to, beyond those it has on by
/// default, and the sites where a Space blocks nothing. The device store keeps
/// the person's list choices and the persistent session's Spaces' sites; any
/// other Space's sites, such as a private one's, live as long as the process.
/// The Spaces of a Sub-Space group share their sites, as they share their
/// site permissions.
internal sealed partial class Device {
    #region Variables

    /// The lists the person turned on or off; any other follows its default.
    private readonly Dictionary<FilterList, bool> filterListChoices = [];
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
        keptBlockingSites.AddRange(records.BlockingSites.Distinct());
    }

    #endregion
}
