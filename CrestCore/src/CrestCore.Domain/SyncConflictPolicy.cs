namespace CrestCore.Domain;

public readonly record struct SyncVersion(ulong Clock, Guid Device) : IComparable<SyncVersion> {
    public int CompareTo(SyncVersion other) {
        int clock = Clock.CompareTo(other.Clock);
        return clock != 0 ? clock : string.Compare(Device.ToString("D"), other.Device.ToString("D"), StringComparison.Ordinal);
    }
}

public sealed record SyncRecordStamp(string Kind, Guid Id, Guid Space, SyncVersion Version,
    string? DeletionReason, double? DeletedAt, double? ActivatedAt);

/// Conflict decisions are shared by every engine and cloud transport.
public static class SyncConflictPolicy {
    public static int Winner(SyncRecordStamp first, SyncRecordStamp second) {
        if (first.Id != second.Id || first.Kind != second.Kind || first.Space != second.Space)
            throw new BrowserRuleException("sync_identity_mismatch");
        if (first.DeletionReason == "explicitDelete") return 0;
        if (second.DeletionReason == "explicitDelete") return 1;
        if (first.DeletedAt is { } firstDeleted && second.Kind == "tab" && second.ActivatedAt > firstDeleted) return 1;
        if (second.DeletedAt is { } secondDeleted && first.Kind == "tab" && first.ActivatedAt > secondDeleted) return 0;
        return first.Version.CompareTo(second.Version) < 0 ? 1 : 0;
    }

    public static int? Latest(double? first, double? second) {
        if (first == second) return null;
        if (first is null) return 1;
        if (second is null) return 0;
        return first > second ? 0 : 1;
    }

    public static TabPlacement RetainedPlacement(TabPlacement first, TabPlacement second)
        => first == TabPlacement.Pinned || second == TabPlacement.Pinned ? TabPlacement.Pinned
            : first == TabPlacement.Saved || second == TabPlacement.Saved ? TabPlacement.Saved : TabPlacement.Current;

    public static bool ActiveTabWins(TabPlacement placement, double activated, SyncVersion tabVersion,
        string archiveReason, double archived, SyncVersion archiveVersion)
        => placement != TabPlacement.Current || archiveReason is "deleted" or "deletedOnAnotherDevice"
            || (archiveReason == "autoCleanup" ? activated > archived : tabVersion.CompareTo(archiveVersion) > 0);
}
