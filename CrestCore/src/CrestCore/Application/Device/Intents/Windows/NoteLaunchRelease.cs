using CrestCore.Application;

namespace CrestCore.Contracts;

/// This launch runs the release `Version`, which the device store keeps as the
/// one this device launched last. When the launch follows an update on a
/// device that completed setup, the first window to send `TakeReleaseNotes`
/// shows the release's notes. It publishes nothing.
public sealed record NoteLaunchRelease(string Version) : WindowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.NoteLaunchRelease(Version);

    #endregion
}
