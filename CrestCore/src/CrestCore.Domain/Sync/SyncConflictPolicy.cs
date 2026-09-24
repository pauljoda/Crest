using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Conflict decisions are shared by every engine and cloud transport.
public static class SyncConflictPolicy {
    #region Actions - Sync

    public static int Winner(SyncRecordStamp first, SyncRecordStamp second) {
        if (first.Id != second.Id || first.Kind != second.Kind || first.Space != second.Space)
            throw new BrowserRuleException(BrowserRuleCodes.SyncIdentityMismatch);
        if (first.DeletionReason?.IsExplicit == true) return 0;
        if (second.DeletionReason?.IsExplicit == true) return 1;
        if (first.DeletedAt is { } firstDeleted && second.Kind == SyncRecordKinds.Tab && second.ActivatedAt > firstDeleted) return 1;
        if (second.DeletedAt is { } secondDeleted && first.Kind == SyncRecordKinds.Tab && first.ActivatedAt > secondDeleted) return 0;
        return first.Version.CompareTo(second.Version) < 0 ? 1 : 0;
    }

    public static int? Latest(double? first, double? second) {
        if (first == second) return null;
        if (first is null) return 1;
        if (second is null) return 0;
        return first > second ? 0 : 1;
    }

    public static bool ActiveTabWins(TabPlacement placement, double activated, SyncVersion tabVersion,
        ArchiveReason archiveReason, double archived, SyncVersion archiveVersion)
        => placement.IsDurable || archiveReason.IsExplicitDeletion
            || (archiveReason.IsCleanup ? activated > archived : tabVersion.CompareTo(archiveVersion) > 0);

    #endregion
}
