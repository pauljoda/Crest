using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.SetupPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Setup

    /// Null when the operation is not a manual-setup or onboarding policy. The
    /// draft itself stays native; these operations admit its edits and decide
    /// what finishing setup does. The workspace import applies the result.
    private static JsonObject? EvaluateSetup(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.SetupSpace => NewSetupSpace(Requests.Space.Decode(request)),
        PolicyOperation.SetupTab => AdmitSetupTab(Requests.Tab.Decode(request)),
        PolicyOperation.SetupReconcile => ReconcileSetup(Requests.Reconcile.Decode(request)),
        PolicyOperation.OnboardingCompletion => CompleteOnboarding(Requests.Completion.Decode(request)),
        PolicyOperation.OnboardingGuide => SetupCodes.GuideAnswer(
            OnboardingCompletionPolicy.ConfirmsGuide(Requests.Guide.Decode(request).Facts)),
        _ => null
    };

    private static JsonObject NewSetupSpace(Requests.Space request) {
        try {
            return SetupCodes.SpaceAnswer(ManualSetupPolicy.NewSpaceNumber(request.DraftCount));
        } catch (BrowserRuleException error) {
            // The setup editor explains the limit the person reached.
            return PolicyAnswers.Error(error);
        }
    }

    private static JsonObject AdmitSetupTab(Requests.Tab request) {
        try {
            return SetupCodes.TabAnswer(ManualSetupPolicy.AdmitTab(request.Placement, request.ExistingPinnedCount,
                request.AddedPinnedCount, request.Url, request.Title));
        } catch (BrowserRuleException error) {
            return PolicyAnswers.Error(error);
        }
    }

    private static JsonObject ReconcileSetup(Requests.Reconcile request) =>
        SetupCodes.ReconcileAnswer(ManualSetupPolicy.Reconcile(request.Drafts, request.Existing));

    private static JsonObject CompleteOnboarding(Requests.Completion request) => SetupCodes.OutcomeAnswer(
        OnboardingCompletionPolicy.Decide(request.EntryPoint, request.HasCompletedSetup, request.IsPrivateBrowsing));

    #endregion
}
