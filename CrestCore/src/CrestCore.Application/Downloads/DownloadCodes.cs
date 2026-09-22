using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the download vocabulary, shared by the ledger commands
/// and the download policy operations. They match the native projection's
/// case names.
internal static class DownloadCodes {
    #region Actions - Encoding

    public static string State(DownloadItemState state) => state switch {
        DownloadItemState.Preparing => "preparing",
        DownloadItemState.AwaitingApproval => "awaitingApproval",
        DownloadItemState.Downloading => "downloading",
        DownloadItemState.Finished => "finished",
        DownloadItemState.BlockedAutomaticDownload => "blockedAutomaticDownload",
        DownloadItemState.Canceled => "canceled",
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

    public static JsonObject Item(DownloadItem item) => new() {
        ["id"] = item.Id.ToString(),
        ["profileID"] = item.Profile.ToString(),
        ["createdAt"] = item.CreatedAt,
        ["filename"] = item.Filename,
        ["destination"] = item.Destination,
        ["progress"] = item.Progress,
        ["telemetry"] = Telemetry(item.Telemetry),
        ["state"] = State(item.State),
        ["message"] = item.Message,
        ["risk"] = item.Risk is { } risk ? new JsonObject {
            ["sanitizedFilename"] = risk.SanitizedFilename,
            ["reasons"] = Reasons(risk.Reasons)
        } : null,
        ["acknowledged"] = item.IsAcknowledged
    };

    #endregion

    #region Actions - Decoding

    public static DownloadRiskReason ParseReason(JsonElement value) => value.GetString() switch {
        "executableOrInstaller" => DownloadRiskReason.ExecutableOrInstaller,
        "deceptiveFilename" => DownloadRiskReason.DeceptiveFilename,
        "dangerousTypeMismatch" => DownloadRiskReason.DangerousTypeMismatch,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidRiskReason)
    };

    public static SitePermissionDecision ParseDecision(string? value) => value switch {
        "ask" => SitePermissionDecision.Ask,
        "grantForSession" => SitePermissionDecision.GrantForSession,
        "denyForSession" => SitePermissionDecision.DenyForSession,
        "grantPersistently" => SitePermissionDecision.GrantPersistently,
        "denyPersistently" => SitePermissionDecision.DenyPersistently,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPermissionDecision)
    };

    public static DownloadTelemetry ParseTelemetry(JsonElement value) {
        Protocol.Members(value, "bytesReceived", "totalBytes", "bytesPerSecond", "estimatedTimeRemaining", "isPaused");
        return new(value.GetProperty("bytesReceived").GetInt64(),
            Optional(value, "totalBytes")?.GetInt64(),
            Optional(value, "bytesPerSecond")?.GetDouble(),
            Optional(value, "estimatedTimeRemaining")?.GetDouble(),
            value.GetProperty("isPaused").GetBoolean());
    }

    public static JsonElement? Optional(JsonElement value, string field) =>
        value.TryGetProperty(field, out var member) && member.ValueKind != JsonValueKind.Null ? member : null;

    /// A string that may be empty, such as a filename an engine could not name.
    public static string AnyText(JsonElement value, string field, int maximumLength) {
        var member = value.GetProperty(field);
        if (member.ValueKind != JsonValueKind.String || member.GetString() is not { } text || text.Length > maximumLength)
            throw new ProtocolException(ProtocolErrorCodes.InvalidString);
        return text;
    }

    #endregion
}
