using CrestCore.Contracts;

namespace CrestCore.Domain;

/// How one launch treats the person's data and what it opens with.
///
/// An isolated launch never reads or writes the installed profile.
/// `UsesEphemeralProfileStorage` keeps page and extension web storage in the
/// same privacy class: both forget, unless a named isolated profile persists
/// both. `PresentsInstalledApplicationUI` is false only under the test runtime.
public sealed record LaunchPlan(bool RequiresIsolation, bool UsesEphemeralProfileStorage,
    bool PresentsInstalledApplicationUI, StartupBehavior Startup);
