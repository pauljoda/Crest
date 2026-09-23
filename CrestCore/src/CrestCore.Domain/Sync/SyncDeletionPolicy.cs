using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Absence alone is not authority to delete a shared tab. Delivery may be
/// incomplete, and closing current tabs does not authorize deleting saved tabs.
public static class SyncDeletionPolicy {
    #region Actions - Sync

    public static string? Reason(string kind, TabPlacement? placement, string? archiveReason,
        bool owningSpaceRemains, string fallback) {
        if (!SyncDeletionReasons.Includes(fallback))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncDeletion);
        if (kind != SyncRecordKinds.Tab) return kind is SyncRecordKinds.Space or SyncRecordKinds.Folder
            ? fallback == SyncDeletionReasons.ExplicitDelete ? fallback : null : fallback;
        if (archiveReason is ArchiveReasons.Deleted or ArchiveReasons.DeletedOnAnotherDevice)
            return SyncDeletionReasons.ExplicitDelete;
        if (archiveReason is not null)
            return placement != TabPlacement.Current ? null : archiveReason == ArchiveReasons.AutoCleanup
                ? SyncDeletionReasons.Retention : SyncDeletionReasons.Superseded;
        return !owningSpaceRemains && fallback == SyncDeletionReasons.ExplicitDelete
            ? SyncDeletionReasons.ExplicitDelete : null;
    }

    #endregion
}
