using CrestCore.Application;

namespace CrestCore.Contracts;

/// Trusts `Tool` from now on, after the person approved it. Refused with
/// `InvalidAutomationTool` for an empty or overlong name or a path that is not
/// absolute, and with `AutomationToolsFull` past the most the device keeps.
public sealed record ApproveAutomationTool(AutomationTool Tool) : AutomationIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAutomation(turn.Changes, automation => automation.Approving(Tool));

    #endregion
}
