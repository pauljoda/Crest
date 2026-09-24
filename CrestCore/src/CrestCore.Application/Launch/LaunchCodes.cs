using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the launch plan. Startup behaviors use the persisted
/// preference's raw values.
internal static class LaunchCodes {
    #region Static Variables

    /// The members of a `launch.plan` policy request.
    public static readonly string[] RequestMembers = ["version", "operation", "platform", "environment", "hasActiveLaunchGate"];
    private static readonly string[] EnvironmentFields = [
        "testRuntime", "previewRuntime", "isolatedSession", "namedProfile", "isolatedCloudSync", "resetSession",
        "showcase", "inMemoryCredentials", "onboardingWelcome", "desktopSetup", "mobileSetup",
        "performanceHarness", "updateTestFeed"
    ];

    #endregion

    #region Actions - Decoding

    public static LaunchEnvironment Environment(JsonElement value) {
        Protocol.Members(value, EnvironmentFields);
        bool Flag(string field) => value.GetProperty(field).GetBoolean();
        return new(Flag("testRuntime"), Flag("previewRuntime"), Flag("isolatedSession"), Flag("namedProfile"),
            Flag("isolatedCloudSync"), Flag("resetSession"), Flag("showcase"), Flag("inMemoryCredentials"),
            Flag("onboardingWelcome"), Flag("desktopSetup"), Flag("mobileSetup"), Flag("performanceHarness"),
            Flag("updateTestFeed"));
    }

    #endregion

    #region Actions - Encoding

    public static JsonObject Plan(LaunchDecision plan) {
        ArgumentNullException.ThrowIfNull(plan);
        return new() {
            ["requiresIsolation"] = plan.RequiresIsolation,
            ["usesEphemeralProfileStorage"] = plan.UsesEphemeralProfileStorage,
            ["presentsInstalledApplicationUI"] = plan.PresentsInstalledApplicationUI,
            ["startupBehavior"] = StoredSessionCodec.Spelling(plan.Startup)
        };
    }

    #endregion
}
