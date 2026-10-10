using CrestCore.Application;

namespace CrestCore.Contracts;

/// Stops trusting `Tool`, so the person is asked again the next time it
/// connects.
public sealed record ForgetAutomationTool(AutomationTool Tool) : AutomationIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAutomation(turn.Changes, automation => automation.Forgetting(Tool));

    #endregion
}
