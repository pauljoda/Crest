using CrestCore.Contracts;

namespace CrestCore.Application;

/// The actions this device keeps on top of Site Controls, which the device
/// store keeps and never syncs.
internal sealed partial class Device {
    #region Variables

    /// The actions the person chose, or null while they keep the defaults,
    /// which then follow a later build's defaults.
    private SiteControlTopActions? chosenSiteControlTopActions;

    internal SiteControlTopActions SiteControlTopActions {
        get {
            lock (gate) return chosenSiteControlTopActions ?? SiteControlTopActions.Default;
        }
    }

    #endregion

    #region Actions - Site Controls

    /// Keeps the actions `revise` makes of the device's own as the person's
    /// choice, and publishes them when they changed.
    internal void ReviseSiteControlTopActions(ChangeFeed changes, Func<SiteControlTopActions, SiteControlTopActions> revise) {
        lock (gate) {
            var current = chosenSiteControlTopActions ?? SiteControlTopActions.Default;
            var revised = revise(current);
            if (revised.Equals(current)) return;
            chosenSiteControlTopActions = revised;
            storage?.EnqueueDevice(Records());
            changes.Publish(new SiteControlTopActionsChanged(revised));
        }
    }

    /// Goes back to the default actions, and publishes them when that
    /// changed what the device shows.
    internal void ResetSiteControlTopActions(ChangeFeed changes) {
        lock (gate) {
            if (chosenSiteControlTopActions is not { } chosen) return;
            chosenSiteControlTopActions = null;
            storage?.EnqueueDevice(Records());
            if (!chosen.Equals(SiteControlTopActions.Default))
                changes.Publish(new SiteControlTopActionsChanged(SiteControlTopActions.Default));
        }
    }

    /// The actions the store kept, as this device offers them, or none while
    /// the person keeps the defaults.
    private static SiteControlTopActions? RestoredSiteControlTopActions(IReadOnlyList<SiteControlAction> kept, DevicePlatform platform) =>
        kept.Count == 0 ? null : SiteControlTopActions.Restored(kept, platform);

    #endregion
}
