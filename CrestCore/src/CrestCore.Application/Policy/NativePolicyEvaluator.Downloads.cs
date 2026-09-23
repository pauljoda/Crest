using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.DownloadPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Downloads

    /// Null when the operation is not a download policy. Progress and risk are
    /// the typed `DownloadProgress` and `DownloadRisk` queries.
    private static JsonObject? EvaluateDownloads(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.DownloadsAutomatic => AutomaticDownload(Requests.Automatic.Decode(request)),
        _ => null
    };

    private static JsonObject AutomaticDownload(Requests.Automatic request) => DownloadCodes.AutomaticAnswer(
        AutomaticDownloadPolicy.Decide(request.UserInitiated, request.UserApprovedRetry, request.SavedDecision,
            request.HasAllowedAutomaticDownload));

    #endregion
}
