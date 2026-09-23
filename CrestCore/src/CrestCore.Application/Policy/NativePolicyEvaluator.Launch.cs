using System.Text.Json;
using System.Text.Json.Nodes;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Launch

    /// Null when the operation is not the launch plan. The platform parses its
    /// own environment into flags; the core decides isolation, profile storage
    /// and installed-app presentation from them before any session exists. The
    /// startup destination here is the one for a person who never chose; the
    /// session's `launch.plan` answers with the saved preference.
    private static JsonObject? EvaluateLaunch(PolicyOperation operation, JsonElement request) =>
        operation == PolicyOperation.LaunchPlan ? LaunchCodes.Plan(LaunchPlanRequest.Decode(request).Plan(null)) : null;

    #endregion
}
