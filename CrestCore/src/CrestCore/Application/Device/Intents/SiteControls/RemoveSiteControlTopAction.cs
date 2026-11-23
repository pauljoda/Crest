using CrestCore.Application;

namespace CrestCore.Contracts;

/// Takes `Action` off the top of Site Controls, unless it is the last action
/// there.
public sealed record RemoveSiteControlTopAction(SiteControlAction Action) : DevicePreferenceIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSiteControlTopActions(turn.Changes, actions => actions.Removing(Action));

    #endregion
}
