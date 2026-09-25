using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Absence alone is not authority to delete a shared record. Delivery may be
/// incomplete, and closing current tabs does not authorize deleting saved tabs.
public static class SyncDeletionPolicy {
    #region Actions - Sync

    /// The reason a Space or folder the staged session no longer holds is
    /// deleted for: only an explicit removal deletes one. `removal` is the
    /// reason of the edit that removed it, or of the stage when none is known.
    public static SyncDeletionReason? Structure(SyncDeletionReason removal) => removal.IsExplicit ? removal : null;

    /// The reason a tab the staged session no longer holds open is deleted
    /// for, or null when its absence authorizes nothing: `placement` is where
    /// it was, `archiveReason` why it was archived, if it was, and
    /// `owningSpaceRemains` whether its Space stays.
    public static SyncDeletionReason? Tab(TabPlacement? placement, ArchiveReason? archiveReason, bool owningSpaceRemains,
        SyncDeletionReason removal) {
        if (archiveReason?.IsExplicitDeletion == true)
            return SyncDeletionReason.ExplicitDelete;
        if (archiveReason is not null)
            return placement?.IsDurable != false ? null : archiveReason.IsCleanup
                ? SyncDeletionReason.Retention : SyncDeletionReason.Superseded;
        return !owningSpaceRemains && removal.IsExplicit ? SyncDeletionReason.ExplicitDelete : null;
    }

    #endregion
}
