namespace CrestCore.Contracts;

/// What the platform read from its launch environment. Each flag is already
/// parsed: a fixture flag is on only for its exact enabled marker, a
/// performance harness is present when its base address is supplied at all,
/// and an update test feed only when it is a loopback address.
/// `HasNamedProfile` marks a named isolated profile, which persists its own
/// state across relaunches.
public sealed record LaunchEnvironment(
    bool IsTestRuntime,
    bool IsPreviewRuntime,
    bool RequestsIsolatedSession,
    bool HasNamedProfile,
    bool RequestsIsolatedCloudSync,
    bool ResetsSession,
    bool PresentsShowcase,
    bool UsesInMemoryCredentials,
    bool ForcesOnboardingWelcome,
    bool ForcesDesktopSetup,
    bool ForcesMobileSetup,
    bool RunsPerformanceHarness,
    bool UsesUpdateTestFeed) {
    #region Static Variables

    /// An installed launch that asks for nothing special.
    public static LaunchEnvironment Installed { get; } = new(false, false, false, false, false, false, false, false, false, false,
        false, false, false);

    #endregion
}
