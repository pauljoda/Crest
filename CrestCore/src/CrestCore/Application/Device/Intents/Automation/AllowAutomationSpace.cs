using CrestCore.Application;

namespace CrestCore.Contracts;

/// Lets local tools reach `SpaceId`, or stops them. Refused with
/// `AutomationSpaceUnavailable` for a Space that is not one of the person's own
/// session, or is being deleted.
public sealed record AllowAutomationSpace(Guid SpaceId, bool Allowed) : AutomationIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        if (Allowed && !device.OffersToAutomation(SpaceId)) throw new Rejected(new AutomationSpaceUnavailable(SpaceId));
        device.ReviseAutomation(turn.Changes, automation => automation.Allowing(SpaceId, Allowed));
    }

    #endregion
}
