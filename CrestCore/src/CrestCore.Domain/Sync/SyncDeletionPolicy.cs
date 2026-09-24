using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Absence alone is not authority to delete a shared tab. Delivery may be
/// incomplete, and closing current tabs does not authorize deleting saved tabs.
public static class SyncDeletionPolicy {
    #region Actions - Sync

    public static string? Reason(string kind, TabPlacement? placement, ArchiveReason? archiveReason,
        bool owningSpaceRemains, string fallback) {
        if (!SyncDeletionReasons.Includes(fallback))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncDeletion);
        if (kind != SyncRecordKinds.Tab) return kind is SyncRecordKinds.Space or SyncRecordKinds.Folder
            ? fallback == SyncDeletionReasons.ExplicitDelete ? fallback : null : fallback;
        if (archiveReason?.IsExplicitDeletion == true)
            return SyncDeletionReasons.ExplicitDelete;
        if (archiveReason is not null)
            return placement?.IsDurable != false ? null : archiveReason.IsCleanup
                ? SyncDeletionReasons.Retention : SyncDeletionReasons.Superseded;
        return !owningSpaceRemains && fallback == SyncDeletionReasons.ExplicitDelete
            ? SyncDeletionReasons.ExplicitDelete : null;
    }

    #endregion
}
