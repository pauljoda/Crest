using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the download policy operations.
internal static class DownloadCodes {
    #region Actions - Encoding

    public static string Reason(DownloadRiskReason reason) => reason switch {
        DownloadRiskReason.ExecutableOrInstaller => "executableOrInstaller",
        DownloadRiskReason.DeceptiveFilename => "deceptiveFilename",
        _ => "dangerousTypeMismatch"
    };

    public static string Action(AutomaticDownloadAction action) => action switch {
        AutomaticDownloadAction.Allow => "allow",
        AutomaticDownloadAction.Deny => "deny",
        _ => "requestPermission"
    };

    public static JsonArray Reasons(IEnumerable<DownloadRiskReason> reasons) =>
        new(reasons.Select(reason => (JsonNode?)JsonValue.Create(Reason(reason))).ToArray());

    public static JsonObject Telemetry(DownloadTelemetry telemetry) => new() {
        ["bytesReceived"] = telemetry.BytesReceived,
        ["totalBytes"] = telemetry.TotalBytes,
        ["bytesPerSecond"] = telemetry.BytesPerSecond,
        ["estimatedTimeRemaining"] = telemetry.EstimatedTimeRemaining,
        ["isPaused"] = telemetry.IsPaused
    };

    public static JsonObject Estimator(DownloadTransferEstimator estimator) => new() {
        ["publishedBytes"] = estimator.PublishedBytes,
        ["knownTotalBytes"] = estimator.KnownTotalBytes,
        ["totalIsUnreliable"] = estimator.TotalIsUnreliable,
        ["measurementBytes"] = estimator.MeasurementBytes,
        ["measurementUptime"] = estimator.MeasurementUptime,
        ["smoothedBytesPerSecond"] = estimator.SmoothedBytesPerSecond
    };

    /// The next estimator state, to send back with the following sample, and
    /// the telemetry this sample publishes.
    public static JsonObject ProgressAnswer(DownloadTransferEstimator next, DownloadTransferSample sample) => new() {
        ["estimator"] = Estimator(next),
        ["telemetry"] = Telemetry(sample.Telemetry),
        ["progress"] = sample.Progress
    };

    public static JsonObject RiskAnswer(DownloadRiskAssessment assessment, bool requiresConfirmation) => new() {
        ["sanitizedFilename"] = assessment.SanitizedFilename,
        ["reasons"] = Reasons(assessment.Reasons),
        ["requiresConfirmation"] = requiresConfirmation
    };

    public static JsonObject AutomaticAnswer(AutomaticDownloadVerdict verdict) => new() {
        ["action"] = Action(verdict.Action),
        ["hasAllowedAutomaticDownload"] = verdict.HasAllowedAutomaticDownload
    };

    #endregion

    #region Actions - Decoding

    public static SitePermissionDecision ParseDecision(string? value) => SitePermissionCodes.ParseDecision(value);

    /// The estimator state a previous `downloads.progress` answer returned.
    public static DownloadTransferEstimator ParseEstimator(JsonElement state) {
        Protocol.Members(state, "publishedBytes", "knownTotalBytes", "totalIsUnreliable", "measurementBytes",
            "measurementUptime", "smoothedBytesPerSecond");
        return new(state.GetProperty("publishedBytes").GetInt64(),
            Optional(state, "knownTotalBytes")?.GetInt64(),
            state.GetProperty("totalIsUnreliable").GetBoolean(),
            Optional(state, "measurementBytes")?.GetInt64(),
            Optional(state, "measurementUptime")?.GetDouble(),
            Optional(state, "smoothedBytesPerSecond")?.GetDouble());
    }

    public static JsonElement? Optional(JsonElement value, string field) => PolicyFields.Optional(value, field);

    #endregion
}
