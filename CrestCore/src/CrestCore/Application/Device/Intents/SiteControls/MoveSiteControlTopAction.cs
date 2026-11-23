using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves `Action` to `Index` among the actions on top of Site Controls,
/// counting from zero, or brings it in there; the others make room after it,
/// and bringing one in while there are four lets the last go. An action this
/// device does not offer changes nothing.
public sealed record MoveSiteControlTopAction(SiteControlAction Action, int Index) : DevicePreferenceIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSiteControlTopActions(turn.Changes, actions => actions.Moving(Action, Index, device.Platform));

    #endregion
}
