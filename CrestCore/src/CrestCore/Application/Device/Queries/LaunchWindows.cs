using CrestCore.Application;

namespace CrestCore.Contracts;

/// What this launch opens on the device, in `Environment`: the saved windows
/// the person left open, back to front, or the one used last, or a new one;
/// the frontmost, which takes the startup choice; the setup that stands in
/// front of them until it finishes, or none; and whether the previous launch
/// ended while it was reopening their pages.
public sealed record LaunchWindows(LaunchEnvironment Environment) : Query<LaunchWindowPlan> {
    #region Actions - Answering

    /// The windows the device store reopens with the frontmost last, and the
    /// setup this device and launch call for.
    internal override LaunchWindowPlan Answer(CrestApp app) {
        var windows = app.Device.LaunchWindows(app.Ids);
        return new(windows, windows[^1], app.Device.LaunchSetup(Environment, app.Device.Platform), app.Device.QuitWhileReopening);
    }

    #endregion
}
