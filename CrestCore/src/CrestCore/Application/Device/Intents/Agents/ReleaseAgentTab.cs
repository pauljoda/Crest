using CrestCore.Application;

namespace CrestCore.Contracts;

/// Lets this connection go of a tab after closing its page, without deleting
/// the tab, affecting another connection or lifting a person-issued stop.
/// Releasing an already absent claim or session changes nothing.
public sealed record ReleaseAgentTab(Guid SessionId, Guid TabId) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgentSessions(turn.Changes, sessions => sessions.Release(SessionId, TabId));

    #endregion
}
