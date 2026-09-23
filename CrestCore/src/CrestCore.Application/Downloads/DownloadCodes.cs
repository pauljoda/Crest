using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the automatic-download policy operation.
internal static class DownloadCodes {
    #region Actions - Encoding

    public static string Action(AutomaticDownloadAction action) => action switch {
        AutomaticDownloadAction.Allow => "allow",
        AutomaticDownloadAction.Deny => "deny",
        _ => "requestPermission"
    };

    public static JsonObject AutomaticAnswer(AutomaticDownloadVerdict verdict) => new() {
        ["action"] = Action(verdict.Action),
        ["hasAllowedAutomaticDownload"] = verdict.HasAllowedAutomaticDownload
    };

    #endregion

    #region Actions - Decoding

    public static SitePermissionDecision ParseDecision(string? value) => SitePermissionCodes.ParseDecision(value);

    #endregion
}
