using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the download policy operations.
internal static class DownloadPolicyRequests {
    #region Actions - Decoding

    public sealed record Automatic(bool UserInitiated, bool UserApprovedRetry, SitePermissionDecision SavedDecision,
        bool HasAllowedAutomaticDownload) {
        public static Automatic Decode(JsonElement request) {
            Members(request, "userInitiated", "userApprovedRetry", "savedDecision", "hasAllowedAutomaticDownload");
            bool initiated = Flag(request, "userInitiated"), approved = Flag(request, "userApprovedRetry");
            var decision = SitePermissionDocument.DecodeDecision(request, "savedDecision");
            return new(initiated, approved, decision, Flag(request, "hasAllowedAutomaticDownload"));
        }
    }

    #endregion
}
