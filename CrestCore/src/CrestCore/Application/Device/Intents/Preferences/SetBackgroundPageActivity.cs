using CrestCore.Application;

namespace CrestCore.Contracts;

/// A page in a tab out of sight keeps doing what `Activity` says, from the
/// next page each engine makes.
public sealed record SetBackgroundPageActivity(BackgroundPageActivity Activity) : DevicePreferenceIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.RevisePages(turn.Changes, pages => pages with { BackgroundActivity = Activity });

    #endregion
}
