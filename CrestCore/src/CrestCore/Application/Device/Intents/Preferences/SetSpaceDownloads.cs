using CrestCore.Application;

namespace CrestCore.Contracts;

/// The downloads of the Space `Preferences` names go where they say on this
/// device.
public sealed record SetSpaceDownloads(SpaceDownloadPreferences Preferences) : DevicePreferenceIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.KeepDownloads(Preferences, turn.Changes);

    #endregion
}
