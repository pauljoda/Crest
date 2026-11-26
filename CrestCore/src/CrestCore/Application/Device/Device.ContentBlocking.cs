using CrestCore.Contracts;

namespace CrestCore.Application;

/// Ad blocking on this device, which holds for every page in every Space: the
/// level it blocks at, which filter lists it subscribes to beyond those the
/// level turns on, and the sites where it blocks nothing. The device store
/// keeps the level, the person's list choices and the sites turned off from a
/// persistent Space; a site turned off from any other Space, such as a private
/// one, lasts as long as the process.
internal sealed partial class Device {
    #region Static Variables

    /// The most filter lists the person may add.
    public const int MaximumCustomFilterLists = ContentBlockingLedger.MaximumCustomFilterLists;
    /// The longest address a custom filter list may have.
    public const int MaximumFilterListAddressLength = ContentBlockingLedger.MaximumFilterListAddressLength;
    /// The longest the person's own filters may be.
    public const int MaximumCustomFiltersBytes = ContentBlockingLedger.MaximumCustomFiltersBytes;

    #endregion

    #region Variables

    private readonly ContentBlockingLedger contentBlocking = new();

    /// The lists the person turned on or off.
    internal IReadOnlyDictionary<FilterList, bool> FilterListChoices {
        get {
            lock (gate) return contentBlocking.FilterListChoices;
        }
    }

    /// What the person chose for filtering.
    internal FilterPreferences FilterChoices {
        get {
            var level = ContentBlockingLevel;
            lock (gate) return contentBlocking.Preferences(level, links.CleansCopiedLinks);
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
                if (contentBlocking.Level is { } chosen) return chosen;
            if (Persistent() is not (_, var authority)) return ContentBlockingLevel.Balanced;
            var level = FirstLevel(authority);
            lock (gate) {
                if (contentBlocking.AdoptLevelIfUnset(level)) storage?.EnqueueDevice(Records());
                return contentBlocking.Level!;
            }
        }
    }

    /// Every site where Crest blocks nothing.
    internal IReadOnlyList<SiteContentBlocking> BlockingSites {
        get {
            lock (gate) return contentBlocking.BlockingSites;
        }
    }

    #endregion

    #region Actions - Filter lists

    /// Whether the persistent session, now attached, gives a device that
    /// never chose a level another level than the Balanced the core answered
    /// before it could.
    internal bool OpeningChangesContentBlockingLevel() {
        lock (gate)
            if (contentBlocking.Level is not null) return false;
        return Persistent() is (_, var authority) && FirstLevel(authority) != ContentBlockingLevel.Balanced;
    }

    /// Blocks at `level` from now on. A level that blocks sets every catalog
    /// list to what it turns on, forgetting the lists the person turned on or
    /// off, from Off as from another level; Off blocks nothing and leaves the
    /// lists as they are. Answers whether that changed anything.
    internal bool SetContentBlockingLevel(ContentBlockingLevel level) {
        ArgumentNullException.ThrowIfNull(level);
        var current = ContentBlockingLevel;
        return UpdateContentBlocking(ledger => ledger.SetLevel(level, current));
    }

    /// Turns `list` on or off for good. Answers whether that changed anything.
    internal bool ChooseFilterList(FilterList list, bool isOn) {
        ArgumentNullException.ThrowIfNull(list);
        return UpdateContentBlocking(ledger => ledger.ChooseFilterList(list, isOn));
    }

    /// Adds the list at `url` as `id`, on. Answers whether that changed
    /// anything: adding an address already added changes nothing. Refused for
    /// an address that is not https, so no one on the network can change the
    /// list on its way, or past the most lists kept.
    internal bool AddCustomFilterList(Guid id, string url) {
        ArgumentNullException.ThrowIfNull(url);
        return UpdateContentBlocking(ledger => ledger.AddCustomFilterList(id, url));
    }

    /// Removes the list the person added as `id`. Answers whether it was there.
    internal bool RemoveCustomFilterList(Guid id) => UpdateContentBlocking(ledger => ledger.RemoveCustomFilterList(id));

    /// Turns the list the person added as `id` on or off. Answers whether that
    /// changed anything.
    internal bool ChooseCustomFilterList(Guid id, bool isOn) =>
        UpdateContentBlocking(ledger => ledger.ChooseCustomFilterList(id, isOn));

    /// Replaces the person's own filters. Answers whether that changed
    /// anything. Refused for filters longer than the core keeps.
    internal bool SetCustomFilters(string text) {
        ArgumentNullException.ThrowIfNull(text);
        return UpdateContentBlocking(ledger => ledger.SetCustomFilters(text));
    }

    /// Removes the lines of the person's filters that `matches`, answering
    /// whether any went.
    internal bool RemoveCustomFilters(Func<string, bool> matches) {
        ArgumentNullException.ThrowIfNull(matches);
        return UpdateContentBlocking(ledger => ledger.RemoveCustomFilters(matches));
    }

    /// Whether a line of the person's filters `matches`.
    internal bool HoldsCustomFilter(Func<string, bool> matches) {
        ArgumentNullException.ThrowIfNull(matches);
        lock (gate) return contentBlocking.HoldsCustomFilter(matches);
    }

    /// Adds `rule` as its own line of the person's filters, unless a line
    /// already holds it. Refused when the filters would grow longer than the
    /// core keeps.
    internal bool AddCustomFilter(string rule) {
        ArgumentException.ThrowIfNullOrWhiteSpace(rule);
        return UpdateContentBlocking(ledger => ledger.AddCustomFilter(rule));
    }

    private bool UpdateContentBlocking(Func<ContentBlockingLedger, bool> edit) {
        lock (gate) {
            if (!edit(contentBlocking)) return false;
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
            var (changed, storesChange) = contentBlocking.SetBlocking(spaceId, origin, blocks, keeps);
            if (!changed) return;
            if (storesChange) storage?.EnqueueDevice(Records());
            changes.Publish(new SiteContentBlockingChanged(contentBlocking.BlockingSites));
        }
    }

    /// Forgets the sites a deleted Space turned blocking off for that only the
    /// process kept. A site turned off from a persistent Space holds
    /// everywhere, so it outlives that Space.
    public void ForgetBlockingSites(Guid spaceId, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        lock (gate) {
            if (!contentBlocking.ForgetPassingSites(spaceId)) return;
            changes.Publish(new SiteContentBlockingChanged(contentBlocking.BlockingSites));
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
        lock (gate) return !contentBlocking.IsExempt(origin);
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
    private void RestoreContentBlocking(DeviceRecords records) => contentBlocking.Restore(records);

    #endregion
}
