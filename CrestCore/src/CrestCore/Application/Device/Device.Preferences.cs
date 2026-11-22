using CrestCore.Contracts;

namespace CrestCore.Application;

/// How this device shows pages, where its Spaces' downloads go, and whether
/// it syncs with iCloud, which the device store keeps and never syncs.
internal sealed partial class Device {
    #region Variables

    private PagePreferences pages = PagePreferences.Default;
    private readonly List<SpaceDownloadPreferences> downloads = [];
    private bool syncsWithICloud = true;

    internal PagePreferences Pages {
        get {
            lock (gate) return pages;
        }
    }

    /// Where each Space's downloads go, for the Spaces that do not keep the
    /// device's Downloads folder.
    internal IReadOnlyList<SpaceDownloadPreferences> Downloads {
        get {
            lock (gate) return [.. downloads];
        }
    }

    /// Whether the person keeps iCloud sync on for this device: on, until
    /// they turn it off.
    internal bool SyncsWithICloud {
        get {
            lock (gate) return syncsWithICloud;
        }
    }

    #endregion

    #region Actions - Preference intents

    /// Runs one device preference intent, publishing what it changed.
    public void Handle(DevicePreferenceIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    /// Keeps the page preferences `revise` makes of the device's own, and
    /// publishes them when they changed.
    internal void RevisePages(ChangeFeed changes, Func<PagePreferences, PagePreferences> revise) {
        lock (gate) {
            var revised = revise(pages);
            if (revised.Equals(pages)) return;
            pages = revised;
            storage?.EnqueueDevice(Records());
            changes.Publish(new PagePreferencesChanged(pages));
        }
    }

    /// Keeps where the downloads of the Space `preferences` names go, and
    /// publishes every Space's when they changed. A Space that keeps the
    /// device's Downloads folder is kept as none.
    internal void KeepDownloads(SpaceDownloadPreferences preferences, ChangeFeed changes) {
        lock (gate) ReviseDownloads(preferences.SpaceId, preferences.IsStandard ? null : preferences, changes);
    }

    /// Forgets where a deleted Space's downloads went.
    public void ForgetDownloads(Guid spaceId, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        lock (gate) ReviseDownloads(spaceId, kept: null, changes);
    }

    /// Keeps whether this device syncs with iCloud.
    internal void KeepSyncsWithICloud(bool syncs) {
        lock (gate) {
            if (syncs == syncsWithICloud) return;
            syncsWithICloud = syncs;
            storage?.EnqueueDevice(Records());
        }
    }

    /// Carries each choice `legacy` holds that the device has not carried
    /// before, in place of its own, and notes each as carried, read or not.
    /// The choices and their markers are saved together, so a launch that
    /// could not save them carries them again. A device that keeps no file
    /// carries nothing.
    internal void Adopt(AdoptDevicePreferences legacy) {
        lock (gate) {
            if (storage is not { } target) return;
            bool carried = false;
            if (Carries(DeviceAdoption.PageZoom) && legacy.DefaultPageZoom is { } zoom)
                pages = pages with { DefaultZoom = PagePreferences.Bounded(zoom) };
            if (Carries(DeviceAdoption.BackgroundPageActivity) && BackgroundPageActivity.Named(legacy.BackgroundPageActivity) is { } activity)
                pages = pages with { BackgroundActivity = activity };
            if (Carries(DeviceAdoption.HighFrameRate) && legacy.AllowsHighFrameRate is { } allowed)
                pages = pages with { AllowsHighFrameRate = allowed };
            if (Carries(DeviceAdoption.CloudSyncEnabled) && legacy.SyncsWithICloud is { } syncs) syncsWithICloud = syncs;
            if (Carries(DeviceAdoption.SpaceDownloads)) {
                foreach (var space in legacy.Downloads.Where(space => !space.IsStandard).DistinctBy(space => space.SpaceId)) {
                    downloads.RemoveAll(kept => kept.SpaceId == space.SpaceId);
                    downloads.Add(space);
                }
            }
            if (carried) target.EnqueueDevice(Records());

            bool Carries(DeviceAdoption adoption) {
                if (!adopted.Add(adoption)) return false;
                carried = true;
                return true;
            }
        }
    }

    /// Keeps `kept` as where the downloads of the Space `spaceId` go, or none,
    /// and publishes every Space's when that changed. The caller holds the
    /// device lock.
    private void ReviseDownloads(Guid spaceId, SpaceDownloadPreferences? kept, ChangeFeed changes) {
        int index = downloads.FindIndex(space => space.SpaceId == spaceId);
        if (index < 0 ? kept is null : downloads[index].Equals(kept)) return;
        if (kept is null) downloads.RemoveAt(index);
        else if (index < 0) downloads.Add(kept);
        else downloads[index] = kept;
        storage?.EnqueueDevice(Records());
        changes.Publish(new DownloadPreferencesChanged([.. downloads]));
    }

    #endregion
}
