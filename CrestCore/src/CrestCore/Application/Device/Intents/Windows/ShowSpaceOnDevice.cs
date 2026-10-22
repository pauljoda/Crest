using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows or hides a Space of the person's own session on this device. A
/// hidden Space keeps syncing, but no window shows it, and no list a window
/// offers names it; each window that showed it moves to the first Space
/// shown. Refused with `UnknownSpace` for a Space that session does not hold
/// or is deleting, and with `CannotHideLastSpace` when no Space would stay
/// shown.
public sealed record ShowSpaceOnDevice(Guid SpaceId, bool Shown) : WindowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ShowSpaceOnDevice(turn.Changes, SpaceId, Shown);

    #endregion
}
