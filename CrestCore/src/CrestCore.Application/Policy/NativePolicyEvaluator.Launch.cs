using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Launch

    /// Null when the operation is not the launch plan. The platform parses its
    /// own environment into flags; the core decides isolation, profile storage,
    /// installed-app presentation and the startup destination from them.
    private static JsonObject? EvaluateLaunch(PolicyOperation operation, JsonElement request) {
        if (operation != PolicyOperation.LaunchPlan) return null;
        Protocol.Members(request, "version", "operation", "platform", "environment", "storedStartupBehavior",
            "hasActiveLaunchGate");
        var plan = LaunchPolicy.Plan(LaunchCodes.Environment(request.GetProperty("environment")),
            DeviceCodes.Platform(request), LaunchCodes.StoredStartup(request),
            request.GetProperty("hasActiveLaunchGate").GetBoolean());
        return new() {
            ["requiresIsolation"] = plan.RequiresIsolation,
            ["usesEphemeralProfileStorage"] = plan.UsesEphemeralProfileStorage,
            ["presentsInstalledApplicationUI"] = plan.PresentsInstalledApplicationUI,
            ["startupBehavior"] = LaunchCodes.Startup(plan.Startup)
        };
    }

    #endregion
}
