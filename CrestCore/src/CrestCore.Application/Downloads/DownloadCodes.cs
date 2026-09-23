using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the download vocabulary, shared by the ledger commands
/// and the download policy operations. They match the native projection's
/// case names.
internal static class DownloadCodes {
    #region Variables

    private static readonly DateTimeOffset ReferenceDate = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    #endregion

    #region Actions - Encoding

    public static string State(DownloadPhase phase) => phase switch {
        DownloadPhase.Preparing => "preparing",
        DownloadPhase.AwaitingApproval => "awaitingApproval",
        DownloadPhase.Downloading => "downloading",
        DownloadPhase.Finished => "finished",
        DownloadPhase.BlockedAutomaticDownload => "blockedAutomaticDownload",
        DownloadPhase.Canceled => "canceled",
        _ => "failed"
    };

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

    public static JsonObject Item(DownloadState item) => new() {
        ["id"] = item.Id.ToString(),
        ["profileID"] = item.ProfileId.ToString(),
        ["createdAt"] = Seconds(item.CreatedAt),
        ["filename"] = item.Filename,
        ["destination"] = item.Destination,
        ["progress"] = item.Progress,
        ["telemetry"] = Telemetry(item.Telemetry),
        ["state"] = State(item.Phase),
        ["message"] = item.Message,
        ["risk"] = item.Risk is { } risk ? new JsonObject {
            ["sanitizedFilename"] = risk.SanitizedFilename,
            ["reasons"] = Reasons(risk.Reasons)
        } : null,
        ["acknowledged"] = item.IsAcknowledged
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

    /// Seconds since 1 January 2001, the native projection's date spelling.
    public static double Seconds(DateTimeOffset date) => (date - ReferenceDate).Ticks / (double)TimeSpan.TicksPerSecond;

    #endregion

    #region Actions - Decoding

    public static DateTimeOffset Date(double seconds) => double.IsFinite(seconds)
        ? ReferenceDate.AddTicks((long)Math.Round(seconds * TimeSpan.TicksPerSecond))
        : throw new ProtocolException(ProtocolErrorCodes.InvalidInput);

    public static DownloadRiskReason ParseReason(JsonElement value) => value.GetString() switch {
        "executableOrInstaller" => DownloadRiskReason.ExecutableOrInstaller,
        "deceptiveFilename" => DownloadRiskReason.DeceptiveFilename,
        "dangerousTypeMismatch" => DownloadRiskReason.DangerousTypeMismatch,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidRiskReason)
    };

    public static SitePermissionDecision ParseDecision(string? value) => SitePermissionCodes.ParseDecision(value);

    public static DownloadTelemetry ParseTelemetry(JsonElement value) {
        Protocol.Members(value, "bytesReceived", "totalBytes", "bytesPerSecond", "estimatedTimeRemaining", "isPaused");
        return new(value.GetProperty("bytesReceived").GetInt64(),
            Optional(value, "totalBytes")?.GetInt64(),
            Optional(value, "bytesPerSecond")?.GetDouble(),
            Optional(value, "estimatedTimeRemaining")?.GetDouble(),
            value.GetProperty("isPaused").GetBoolean());
    }

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

    /// A string that may be empty, such as a filename an engine could not name.
    public static string AnyText(JsonElement value, string field, int maximumLength) =>
        PolicyFields.AnyText(value, field, maximumLength);

    #endregion
}
