using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Downloads

    /// Null when the operation is not a download policy.
    private static JsonObject? EvaluateDownloads(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.DownloadsProgress:
                Protocol.Members(request, "version", "operation", "estimator", "completedUnitCount", "totalUnitCount",
                    "fractionCompleted", "isPaused", "uptime");
                var estimator = DownloadCodes.Optional(request, "estimator") is { } state ? Estimator(state) : default;
                var (next, sample) = estimator.Sample(request.GetProperty("completedUnitCount").GetInt64(),
                    request.GetProperty("totalUnitCount").GetInt64(), request.GetProperty("fractionCompleted").GetDouble(),
                    request.GetProperty("isPaused").GetBoolean(), request.GetProperty("uptime").GetDouble());
                return new() {
                    ["estimator"] = new JsonObject {
                        ["publishedBytes"] = next.PublishedBytes,
                        ["knownTotalBytes"] = next.KnownTotalBytes,
                        ["totalIsUnreliable"] = next.TotalIsUnreliable,
                        ["measurementBytes"] = next.MeasurementBytes,
                        ["measurementUptime"] = next.MeasurementUptime,
                        ["smoothedBytesPerSecond"] = next.SmoothedBytesPerSecond
                    },
                    ["telemetry"] = DownloadCodes.Telemetry(sample.Telemetry),
                    ["progress"] = sample.Progress
                };
            case PolicyOperation.DownloadsRisk:
                Protocol.Members(request, "version", "operation", "suggestedFilename", "sanitizedFilename", "mimeType",
                    "extensionRunsCode", "mimeTypeRunsCode", "typesRelated", "userInitiated");
                var assessment = DownloadRiskPolicy.Assess(new(
                    DownloadCodes.AnyText(request, "suggestedFilename", DownloadLedger.MaximumFilenameLength * 4),
                    Protocol.Text(request, "sanitizedFilename", DownloadLedger.MaximumFilenameLength),
                    Protocol.OptionalText(request, "mimeType", 255),
                    request.GetProperty("extensionRunsCode").GetBoolean(),
                    request.GetProperty("mimeTypeRunsCode").GetBoolean(),
                    DownloadCodes.Optional(request, "typesRelated")?.GetBoolean()));
                return new() {
                    ["sanitizedFilename"] = assessment.SanitizedFilename,
                    ["reasons"] = DownloadCodes.Reasons(assessment.Reasons),
                    ["requiresConfirmation"] = DownloadRiskPolicy.RequiresConfirmation(assessment,
                        request.GetProperty("userInitiated").GetBoolean())
                };
            case PolicyOperation.DownloadsAutomatic:
                Protocol.Members(request, "version", "operation", "userInitiated", "userApprovedRetry", "savedDecision",
                    "hasAllowedAutomaticDownload");
                var verdict = AutomaticDownloadPolicy.Decide(request.GetProperty("userInitiated").GetBoolean(),
                    request.GetProperty("userApprovedRetry").GetBoolean(),
                    DownloadCodes.ParseDecision(Protocol.Text(request, "savedDecision")),
                    request.GetProperty("hasAllowedAutomaticDownload").GetBoolean());
                return new() {
                    ["action"] = DownloadCodes.Action(verdict.Action),
                    ["hasAllowedAutomaticDownload"] = verdict.HasAllowedAutomaticDownload
                };
            default:
                return null;
        }
    }

    private static DownloadTransferEstimator Estimator(JsonElement state) {
        Protocol.Members(state, "publishedBytes", "knownTotalBytes", "totalIsUnreliable", "measurementBytes",
            "measurementUptime", "smoothedBytesPerSecond");
        return new(state.GetProperty("publishedBytes").GetInt64(),
            DownloadCodes.Optional(state, "knownTotalBytes")?.GetInt64(),
            state.GetProperty("totalIsUnreliable").GetBoolean(),
            DownloadCodes.Optional(state, "measurementBytes")?.GetInt64(),
            DownloadCodes.Optional(state, "measurementUptime")?.GetDouble(),
            DownloadCodes.Optional(state, "smoothedBytesPerSecond")?.GetDouble());
    }

    #endregion
}
