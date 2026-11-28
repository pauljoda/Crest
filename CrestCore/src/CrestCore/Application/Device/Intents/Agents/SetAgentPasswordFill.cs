using CrestCore.Application;

namespace CrestCore.Contracts;

/// Lets agents ask Crest to fill a saved password into a page's sign-in form,
/// or stops them. Crest fills it itself, once the person agrees, so an agent
/// never reads the password.
public sealed record SetAgentPasswordFill(bool FillsPasswords) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAgents(turn.Changes, preferences => preferences with { FillsPasswords = FillsPasswords });

    #endregion
}
