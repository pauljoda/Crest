using CrestCore.Application;

namespace CrestCore.Contracts;

/// Puts `Action` in `Slot` of the actions on top of Site Controls, counting
/// from zero. An action already among them trades places with the one in
/// `Slot`, and the slot after the last, while there are fewer than four,
/// takes a new one; one this device does not offer, or any other slot,
/// changes nothing.
public sealed record PlaceSiteControlTopAction(SiteControlAction Action, int Slot) : DevicePreferenceIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSiteControlTopActions(turn.Changes, actions => actions.Placing(Action, Slot, device.Platform));

    #endregion
}
