using CrestCore.Application;

namespace CrestCore.Contracts;

/// Carries the page, download and iCloud sync choices an installed release
/// kept in its defaults into the device store, each once, and publishes the
/// page and download preferences. A choice the release never saved, or one
/// this build cannot read, leaves the device's own, and counts as carried all
/// the same, so a later launch never reads that default again; the release's
/// own copy stays where it is. A device that keeps no file carries nothing
/// and still publishes its preferences, so the platform reads them from
/// launch, together with the actions on top of Site Controls.
public sealed record AdoptDevicePreferences(double? DefaultPageZoom, string? BackgroundPageActivity, bool? AllowsHighFrameRate,
    bool? SyncsWithICloud, IReadOnlyList<SpaceDownloadPreferences> Downloads) : DevicePreferenceIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        device.Adopt(this);
        turn.Changes.Publish(new PagePreferencesChanged(device.Pages));
        turn.Changes.Publish(new DownloadPreferencesChanged(device.Downloads));
        turn.Changes.Publish(new SiteControlTopActionsChanged(device.SiteControlTopActions));
    }

    #endregion
}
