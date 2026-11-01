using CrestCore.Application;

namespace CrestCore.Contracts;

/// Lets agents reach `SpaceId` and every Space of its group, which browse with
/// one session, or stops them; agents using their tabs let them go. Refused
/// with `AgentSpaceUnavailable` for a Space that is not one of the person's
/// own session, or is being deleted.
public sealed record AllowAgentSpace(Guid SpaceId, bool Allowed) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        if (Allowed && !device.OffersToAgents(SpaceId)) throw new Rejected(new AgentSpaceUnavailable(SpaceId));
        var group = device.AgentGroup(SpaceId);
        device.ReviseAgents(turn.Changes, preferences => group.Aggregate(preferences, (revised, space) => revised.Allowing(space, Allowed)));
    }

    #endregion
}
