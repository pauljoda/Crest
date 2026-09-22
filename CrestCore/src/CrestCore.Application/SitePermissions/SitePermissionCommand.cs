using CrestCore.Domain;

namespace CrestCore.Application;

internal enum SitePermissionCommand {
    Decision,
    Load,
    MediaDecision,
    Records,
    ResetRecord,
    ResetSession,
    ResetSpace,
    Set,
}

internal static class SitePermissionCommandCodes {
    #region Actions - Decoding

    public static SitePermissionCommand Parse(string? value) => value switch {
        "decision" => SitePermissionCommand.Decision,
        "load" => SitePermissionCommand.Load,
        "media_decision" => SitePermissionCommand.MediaDecision,
        "records" => SitePermissionCommand.Records,
        "reset_record" => SitePermissionCommand.ResetRecord,
        "reset_session" => SitePermissionCommand.ResetSession,
        "reset_space" => SitePermissionCommand.ResetSpace,
        "set" => SitePermissionCommand.Set,
        _ => throw new BrowserRuleException(BrowserRuleCodes.UnknownSitePermissionCommand)
    };

    #endregion
}
