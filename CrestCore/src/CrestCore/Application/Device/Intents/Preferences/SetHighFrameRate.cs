using CrestCore.Application;

namespace CrestCore.Contracts;

/// Pages may draw faster than 60 frames a second when `Allowed`, from the
/// next page each engine makes.
public sealed record SetHighFrameRate(bool Allowed) : DevicePreferenceIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.RevisePages(turn.Changes, pages => pages with { AllowsHighFrameRate = Allowed });

    #endregion
}
