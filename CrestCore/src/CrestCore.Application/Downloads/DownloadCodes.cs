using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the automatic-download policy operation.
internal static class DownloadCodes {
    #region Actions - Encoding

    public static JsonObject AutomaticAnswer(AutomaticDownloadVerdict verdict) => new() {
        ["action"] = verdict.Action.Name,
        ["hasAllowedAutomaticDownload"] = verdict.HasAllowedAutomaticDownload
    };

    #endregion
}
