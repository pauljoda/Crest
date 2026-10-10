using CrestCore.Application;

namespace CrestCore.Contracts;

/// This device's automation preferences.
public sealed record GetAutomationPreferences : Query<AutomationPreferences> {
    #region Actions - Answering

    internal override AutomationPreferences Answer(CrestApp app) => app.Device.Automation;

    #endregion
}
