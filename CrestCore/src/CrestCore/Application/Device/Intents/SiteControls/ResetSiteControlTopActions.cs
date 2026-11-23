using CrestCore.Application;

namespace CrestCore.Contracts;

/// Brings back the four default actions on top of Site Controls, which
/// follow the defaults from then on.
public sealed record ResetSiteControlTopActions : DevicePreferenceIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ResetSiteControlTopActions(turn.Changes);

    #endregion
}
