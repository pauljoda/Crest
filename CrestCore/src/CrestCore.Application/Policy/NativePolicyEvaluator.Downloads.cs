using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.DownloadPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Downloads

    /// Null when the operation is not a download policy.
    private static JsonObject? EvaluateDownloads(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.DownloadsProgress => SampleDownload(Requests.Progress.Decode(request)),
        PolicyOperation.DownloadsRisk => AssessDownload(Requests.Risk.Decode(request)),
        PolicyOperation.DownloadsAutomatic => AutomaticDownload(Requests.Automatic.Decode(request)),
        _ => null
    };

    private static JsonObject SampleDownload(Requests.Progress request) {
        var (next, sample) = request.Estimator.Sample(request.CompletedUnitCount, request.TotalUnitCount,
            request.FractionCompleted, request.IsPaused, request.Uptime);
        return DownloadCodes.ProgressAnswer(next, sample);
    }

    private static JsonObject AssessDownload(Requests.Risk request) {
        var assessment = DownloadRiskPolicy.Assess(request.Facts);
        return DownloadCodes.RiskAnswer(assessment, DownloadRiskPolicy.RequiresConfirmation(assessment, request.UserInitiated));
    }

    private static JsonObject AutomaticDownload(Requests.Automatic request) => DownloadCodes.AutomaticAnswer(
        AutomaticDownloadPolicy.Decide(request.UserInitiated, request.UserApprovedRetry, request.SavedDecision,
            request.HasAllowedAutomaticDownload));

    #endregion
}
