using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.TabPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Tabs

    /// Null when the operation is not a page-residency, process-recovery or
    /// tab-dismissal policy.
    private static JsonObject? EvaluateTabs(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.ResidencyReleaseLimit => ReleaseLimit(Requests.ReleaseLimit.Decode(request)),
        PolicyOperation.ResidencyReleasePlan => ReleasePlan(Requests.ReleasePlan.Decode(request)),
        PolicyOperation.ResidencyProcessRecovery => TabPolicyCodes.RecoveryAnswer(
            PageProcessRecoveryPolicy.Decide(Requests.ProcessRecovery.Decode(request).ConsecutiveTerminations)),
        PolicyOperation.TabsDismissal => Dismiss(Requests.Dismissal.Decode(request)),
        _ => null
    };

    private static JsonObject ReleaseLimit(Requests.ReleaseLimit request) => TabPolicyCodes.ReleaseLimitAnswer(
        PageResidencyPolicy.ReleaseLimit(request.Level, request.EligiblePageCount, request.Platform));

    private static JsonObject ReleasePlan(Requests.ReleasePlan request) {
        var plan = PageResidencyPolicy.ReleasePlan(request.Candidates, request.Level, request.Platform, request.FocusedIndex);
        return TabPolicyCodes.ReleasePlanAnswer(plan.OffScreen, plan.PresentedFallback);
    }

    private static JsonObject Dismiss(Requests.Dismissal request) => TabPolicyCodes.DismissalAnswer(
        TabDismissalPolicy.Decide(request.Placement, request.IsStartPage, request.TabCount));

    #endregion
}
