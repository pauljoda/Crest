using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the launch plan. Startup behaviors use the persisted
/// preference's raw values.
internal static class LaunchCodes {
    #region Variables

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

    /// A stored value this build does not recognise reads as no preference.
    public static StartupBehavior? StoredStartup(JsonElement request) {
        var stored = request.GetProperty("storedStartupBehavior");
        if (stored.ValueKind is not (JsonValueKind.String or JsonValueKind.Null))
            throw new ProtocolException(ProtocolErrorCodes.InvalidString);
        return stored.ValueKind == JsonValueKind.Null ? null : stored.GetString() switch {
            "showStartPage" => StartupBehavior.ShowStartPage,
            "lastActiveTab" => StartupBehavior.LastActiveTab,
            _ => null
        };
    }

    #endregion

    #region Actions - Encoding

    public static string Startup(StartupBehavior behavior) =>
        behavior == StartupBehavior.LastActiveTab ? "lastActiveTab" : "showStartPage";

    #endregion
}
