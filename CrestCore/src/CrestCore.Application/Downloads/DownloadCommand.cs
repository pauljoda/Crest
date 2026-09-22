using CrestCore.Domain;

namespace CrestCore.Application;

internal enum DownloadCommand {
    AcknowledgeProfile,
    AssessRisk,
    AwaitApproval,
    Begin,
    Block,
    Cancel,
    Destination,
    Expire,
    Fail,
    Finish,
    Remove,
    RemoveProfile,
    Restart,
    Transfer,
}

internal static class DownloadCommandCodes {
    #region Actions - Decoding

    public static DownloadCommand Parse(string? value) => value switch {
        "acknowledge_profile" => DownloadCommand.AcknowledgeProfile,
        "assess_risk" => DownloadCommand.AssessRisk,
        "await_approval" => DownloadCommand.AwaitApproval,
        "begin" => DownloadCommand.Begin,
        "block" => DownloadCommand.Block,
        "cancel" => DownloadCommand.Cancel,
        "destination" => DownloadCommand.Destination,
        "expire" => DownloadCommand.Expire,
        "fail" => DownloadCommand.Fail,
        "finish" => DownloadCommand.Finish,
        "remove" => DownloadCommand.Remove,
        "remove_profile" => DownloadCommand.RemoveProfile,
        "restart" => DownloadCommand.Restart,
        "transfer" => DownloadCommand.Transfer,
        _ => throw new BrowserRuleException(BrowserRuleCodes.UnknownDownloadCommand)
    };

    #endregion
}
