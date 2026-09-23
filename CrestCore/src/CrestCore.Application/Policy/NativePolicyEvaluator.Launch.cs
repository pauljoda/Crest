using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Launch

    /// Null when the operation is not the launch plan. The platform parses its
    /// own environment into flags; the core decides isolation, profile storage
    /// and installed-app presentation from them before any session exists. The
    /// startup destination here is the one for a person who never chose; the
    /// session's `launch.plan` answers with the saved preference.
    private static JsonObject? EvaluateLaunch(PolicyOperation operation, JsonElement request) {
        if (operation != PolicyOperation.LaunchPlan) return null;
        Protocol.Members(request, LaunchCodes.RequestMembers);
        return LaunchCodes.Plan(PlanLaunch(request, null));
    }

    /// Shared with the session's `launch.plan`, which supplies the owned startup
    /// preference.
    internal static LaunchPlan PlanLaunch(JsonElement request, StartupBehavior? storedStartup) =>
        LaunchPolicy.Plan(LaunchCodes.Environment(request.GetProperty("environment")), DeviceCodes.Platform(request),
            storedStartup, request.GetProperty("hasActiveLaunchGate").GetBoolean());

    #endregion
}
