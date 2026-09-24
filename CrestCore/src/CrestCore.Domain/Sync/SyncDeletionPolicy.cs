using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Absence alone is not authority to delete a shared tab. Delivery may be
/// incomplete, and closing current tabs does not authorize deleting saved tabs.
public static class SyncDeletionPolicy {
    #region Actions - Sync

    /// The reason a record the staged session no longer holds is deleted for,
    /// or null when its absence authorizes nothing. `removal` is the reason of
    /// the edit that removed the record, or of the stage when none is known.
    public static SyncDeletionReason? Reason(string kind, TabPlacement? placement, ArchiveReason? archiveReason,
        bool owningSpaceRemains, SyncDeletionReason removal) {
        if (kind != SyncRecordKinds.Tab) return kind is SyncRecordKinds.Space or SyncRecordKinds.Folder
            ? removal.IsExplicit ? removal : null : removal;
        if (archiveReason?.IsExplicitDeletion == true)
            return SyncDeletionReason.ExplicitDelete;
        if (archiveReason is not null)
            return placement?.IsDurable != false ? null : archiveReason.IsCleanup
                ? SyncDeletionReason.Retention : SyncDeletionReason.Superseded;
        return !owningSpaceRemains && removal.IsExplicit ? SyncDeletionReason.ExplicitDelete : null;
    }

    #endregion
}
