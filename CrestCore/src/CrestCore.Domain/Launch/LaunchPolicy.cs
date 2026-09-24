using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Which launches must stay out of the installed profile, and what a window
/// opens with.
public static class LaunchPolicy {
    #region Variables

    /// The documented default for a person who never chose.
    public const StartupBehavior DefaultStartup = StartupBehavior.ShowStartPage;

    #endregion

    #region Actions - Launch

    /// `storedStartup` is the saved preference, null when absent or unreadable.
    /// `hasActiveLaunchGate` is true while first-run setup owns the initial
    /// destination.
    public static LaunchPlan Plan(LaunchEnvironmentFacts facts, DevicePlatform platform, StartupBehavior? storedStartup,
        bool hasActiveLaunchGate) {
        ArgumentNullException.ThrowIfNull(facts);
        bool isolated = RequiresIsolation(facts);
        return new(isolated, isolated && !facts.HasNamedProfile, !facts.IsTestRuntime,
            Startup(facts, platform, isolated, storedStartup, hasActiveLaunchGate));
    }

    /// Every test, preview, fixture, review and performance launch is isolated.
    public static bool RequiresIsolation(LaunchEnvironmentFacts facts) {
        ArgumentNullException.ThrowIfNull(facts);
        return facts.IsTestRuntime || facts.IsPreviewRuntime || facts.RequestsIsolatedSession
            || facts.RequestsIsolatedCloudSync || facts.ResetsSession || facts.PresentsShowcase
            || facts.UsesInMemoryCredentials || facts.ForcesOnboardingWelcome || facts.ForcesDesktopSetup
            || facts.ForcesMobileSetup || facts.RunsPerformanceHarness || facts.UsesUpdateTestFeed;
    }

    /// The mobile showcase always opens on the Start Page. Setup and isolated
    /// launches restore the last active tab so a fixture opens where it was
    /// staged; everyone else gets their saved choice.
    private static StartupBehavior Startup(LaunchEnvironmentFacts facts, DevicePlatform platform, bool isolated,
        StartupBehavior? stored, bool hasActiveLaunchGate) {
        if (platform == DevicePlatform.Mobile && facts.PresentsShowcase) return StartupBehavior.ShowStartPage;
        if (hasActiveLaunchGate || isolated) return StartupBehavior.LastActiveTab;
        return stored ?? DefaultStartup;
    }

    #endregion
}
