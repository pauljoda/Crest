namespace CrestCore.Contracts;

/// How one launch treats the person's data and what its first window opens.
/// An isolated launch never reads or writes the installed profile.
/// `UsesEphemeralProfileStorage` keeps page and extension web storage in the
/// same privacy class: both forget, unless a named isolated profile persists
/// both. `PresentsInstalledApplicationUI` is false only under the test runtime.
public sealed record LaunchDecision(bool RequiresIsolation, bool UsesEphemeralProfileStorage, bool PresentsInstalledApplicationUI,
    StartupBehavior Startup);
