namespace CrestCore.Application;

internal enum PolicyOperation {
    Unknown,
    AddressIntent,
    DownloadsAutomatic,
    DownloadsProgress,
    DownloadsRisk,
    HistoryNormalize,
    HistoryRemoveRange,
    HistoryVisit,
    NavigationLink,
    NavigationModifiedLink,
    RecordsExpired,
    ResidencyProcessRecovery,
    ResidencyReleaseLimit,
    ResidencyReleasePlan,
    TabsDismissal,
}

internal static class PolicyOperationCodes {
    #region Actions - Decoding

    public static PolicyOperation Parse(string? value) => value switch {
        "address.intent" => PolicyOperation.AddressIntent,
        "downloads.automatic" => PolicyOperation.DownloadsAutomatic,
        "downloads.progress" => PolicyOperation.DownloadsProgress,
        "downloads.risk" => PolicyOperation.DownloadsRisk,
        "history.normalize" => PolicyOperation.HistoryNormalize,
        "history.remove_range" => PolicyOperation.HistoryRemoveRange,
        "history.visit" => PolicyOperation.HistoryVisit,
        "navigation.link" => PolicyOperation.NavigationLink,
        "navigation.modified_link" => PolicyOperation.NavigationModifiedLink,
        "records.expired" => PolicyOperation.RecordsExpired,
        "residency.process_recovery" => PolicyOperation.ResidencyProcessRecovery,
        "residency.release_limit" => PolicyOperation.ResidencyReleaseLimit,
        "residency.release_plan" => PolicyOperation.ResidencyReleasePlan,
        "tabs.dismissal" => PolicyOperation.TabsDismissal,
        _ => PolicyOperation.Unknown
    };

    #endregion
}
