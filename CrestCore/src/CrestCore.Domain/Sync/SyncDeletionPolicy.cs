namespace CrestCore.Domain;

/// Absence alone is not authority to delete a shared tab. Delivery may be
/// incomplete, and closing current tabs does not authorize deleting saved tabs.
public static class SyncDeletionPolicy {
    #region Actions - Sync

    public static string? Reason(string kind, TabPlacement? placement, string? archiveReason,
        bool owningSpaceRemains, string fallback) {
        if (fallback is not ("explicitDelete" or "superseded" or "retention"))
            throw new BrowserRuleException("invalid_sync_deletion");
        if (kind != "tab") return kind is "space" or "folder"
            ? fallback == "explicitDelete" ? fallback : null : fallback;
        if (archiveReason is "deleted" or "deletedOnAnotherDevice") return "explicitDelete";
        if (archiveReason is not null)
            return placement != TabPlacement.Current ? null : archiveReason == "autoCleanup" ? "retention" : "superseded";
        return !owningSpaceRemains && fallback == "explicitDelete" ? "explicitDelete" : null;
    }

    #endregion
}
