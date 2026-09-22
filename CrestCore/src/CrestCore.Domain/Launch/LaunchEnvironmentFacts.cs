namespace CrestCore.Domain;

/// What the platform read from its launch environment. Each flag is already
/// parsed: a fixture flag is on only for its exact enabled marker, a
/// performance harness is present when its base address is supplied at all, and
/// an update test feed only when it is a loopback address.
public sealed record LaunchEnvironmentFacts {
    #region Variables

    public bool IsTestRuntime { get; init; }
    public bool IsPreviewRuntime { get; init; }
    public bool RequestsIsolatedSession { get; init; }
    /// A named isolated profile persists its own state across relaunches.
    public bool HasNamedProfile { get; init; }
    public bool RequestsIsolatedCloudSync { get; init; }
    public bool ResetsSession { get; init; }
    public bool PresentsShowcase { get; init; }
    public bool UsesInMemoryCredentials { get; init; }
    public bool ForcesOnboardingWelcome { get; init; }
    public bool ForcesDesktopSetup { get; init; }
    public bool ForcesMobileSetup { get; init; }
    public bool RunsPerformanceHarness { get; init; }
    public bool UsesUpdateTestFeed { get; init; }

    #endregion
}
