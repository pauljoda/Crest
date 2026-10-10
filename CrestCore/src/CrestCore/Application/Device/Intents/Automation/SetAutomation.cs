using CrestCore.Application;

namespace CrestCore.Contracts;

/// Lets local tools control Crest, or stops them. The Spaces and tools the
/// person chose are kept either way.
public sealed record SetAutomation(bool IsOn) : AutomationIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseAutomation(turn.Changes, automation => automation with { IsOn = IsOn });

    #endregion
}
