using CrestCore.Application;

namespace CrestCore.Contracts;

/// Pages start at `Zoom` on this device, within the range a page may start
/// at; a value that is not a number starts them at the standard zoom.
public sealed record SetDefaultPageZoom(double Zoom) : DevicePreferenceIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.RevisePages(turn.Changes, pages => pages with { DefaultZoom = PagePreferences.Bounded(Zoom) });

    #endregion
}
