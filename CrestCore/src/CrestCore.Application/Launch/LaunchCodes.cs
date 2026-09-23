using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the launch plan. Startup behaviors use the persisted
/// preference's raw values.
internal static class LaunchCodes {
    #region Variables

    /// The members of a `launch.plan` request, as a policy operation or a session read.
    public static readonly string[] RequestMembers = ["version", "operation", "platform", "environment", "hasActiveLaunchGate"];
    private static readonly string[] EnvironmentFields = [
        "testRuntime", "previewRuntime", "isolatedSession", "namedProfile", "isolatedCloudSync", "resetSession",
        "showcase", "inMemoryCredentials", "onboardingWelcome", "desktopSetup", "mobileSetup",
        "performanceHarness", "updateTestFeed"
    ];

    #endregion

    #region Actions - Decoding

    public static LaunchEnvironmentFacts Environment(JsonElement value) {
        Protocol.Members(value, EnvironmentFields);
        bool Flag(string field) => value.GetProperty(field).GetBoolean();
        return new() {
            IsTestRuntime = Flag("testRuntime"),
            IsPreviewRuntime = Flag("previewRuntime"),
            RequestsIsolatedSession = Flag("isolatedSession"),
            HasNamedProfile = Flag("namedProfile"),
            RequestsIsolatedCloudSync = Flag("isolatedCloudSync"),
            ResetsSession = Flag("resetSession"),
            PresentsShowcase = Flag("showcase"),
            UsesInMemoryCredentials = Flag("inMemoryCredentials"),
            ForcesOnboardingWelcome = Flag("onboardingWelcome"),
            ForcesDesktopSetup = Flag("desktopSetup"),
            ForcesMobileSetup = Flag("mobileSetup"),
            RunsPerformanceHarness = Flag("performanceHarness"),
            UsesUpdateTestFeed = Flag("updateTestFeed")
        };
    }

    #endregion

    #region Actions - Encoding

    public static string Startup(StartupBehavior behavior) =>
        behavior == StartupBehavior.LastActiveTab ? "lastActiveTab" : "showStartPage";

    public static JsonObject Plan(LaunchPlan plan) {
        ArgumentNullException.ThrowIfNull(plan);
        return new() {
            ["requiresIsolation"] = plan.RequiresIsolation,
            ["usesEphemeralProfileStorage"] = plan.UsesEphemeralProfileStorage,
            ["presentsInstalledApplicationUI"] = plan.PresentsInstalledApplicationUI,
            ["startupBehavior"] = Startup(plan.Startup)
        };
    }

    #endregion
}
