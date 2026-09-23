using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the download policy operations.
internal static class DownloadPolicyRequests {
    #region Actions - Decoding

    /// One progress sample. A first sample carries no estimator state.
    public sealed record Progress(DownloadTransferEstimator Estimator, long CompletedUnitCount, long TotalUnitCount,
        double FractionCompleted, bool IsPaused, double Uptime) {
        public static Progress Decode(JsonElement request) {
            Members(request, "estimator", "completedUnitCount", "totalUnitCount", "fractionCompleted", "isPaused", "uptime");
            var estimator = Optional(request, "estimator") is { } state ? DownloadCodes.ParseEstimator(state) : default;
            long completed = Long(request, "completedUnitCount"), total = Long(request, "totalUnitCount");
            double fraction = Number(request, "fractionCompleted");
            bool paused = Flag(request, "isPaused");
            return new(estimator, completed, total, fraction, paused, Number(request, "uptime"));
        }
    }

    public sealed record Risk(DownloadRiskFacts Facts, bool UserInitiated) {
        public static Risk Decode(JsonElement request) {
            Members(request, "suggestedFilename", "sanitizedFilename", "mimeType", "extensionRunsCode", "mimeTypeRunsCode",
                "typesRelated", "userInitiated");
            var facts = new DownloadRiskFacts(
                AnyText(request, "suggestedFilename", DownloadLedger.MaximumFilenameLength * 4),
                Protocol.Text(request, "sanitizedFilename", DownloadLedger.MaximumFilenameLength),
                Protocol.OptionalText(request, "mimeType", 255),
                Flag(request, "extensionRunsCode"), Flag(request, "mimeTypeRunsCode"), OptionalFlag(request, "typesRelated"));
            return new(facts, Flag(request, "userInitiated"));
        }
    }

    public sealed record Automatic(bool UserInitiated, bool UserApprovedRetry, SitePermissionDecision SavedDecision,
        bool HasAllowedAutomaticDownload) {
        public static Automatic Decode(JsonElement request) {
            Members(request, "userInitiated", "userApprovedRetry", "savedDecision", "hasAllowedAutomaticDownload");
            bool initiated = Flag(request, "userInitiated"), approved = Flag(request, "userApprovedRetry");
            var decision = DownloadCodes.ParseDecision(Protocol.Text(request, "savedDecision"));
            return new(initiated, approved, decision, Flag(request, "hasAllowedAutomaticDownload"));
        }
    }

    #endregion
}
