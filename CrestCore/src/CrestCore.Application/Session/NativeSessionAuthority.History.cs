using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// When the session was last swept, and the retention each Space had then.
    private sealed record SweepMark(DateTimeOffset At, IReadOnlyList<SpaceRetention> Retention) {
        #region Actions - Throttling

        /// Whether a sweep at `now` of `session` would repeat this one: it comes
        /// less than `MinimumSweepSpacing` later, and no Space's retention
        /// changed. A clock that went backwards never holds a sweep back.
        public bool Covers(DateTimeOffset now, SessionState session) =>
            now >= At && now - At < MinimumSweepSpacing && Retention.SequenceEqual(SpaceRetention.Of(session));

        #endregion
    }

    /// What a Space keeps and for how long.
    private sealed record SpaceRetention(Guid SpaceId, CurrentTabCleanup Cleanup, DataRetentionPreferences Records) {
        #region Actions - Reading

        public static IReadOnlyList<SpaceRetention> Of(SessionState session) => [.. session.Spaces.Select(space =>
            new SpaceRetention(space.Id, space.Settings.BrowsingPreferences.CurrentTabCleanup, space.Settings.BrowsingPreferences.DataRetention))];

        #endregion
    }

    #endregion

    #region Variables

    /// The shortest gap between two sweeps of one session. Windows becoming
    /// active together, or an activation landing on a periodic sweep, sweep once.
    private static readonly TimeSpan MinimumSweepSpacing = TimeSpan.FromMinutes(1);

    /// The last sweep this session ran; null until it runs one.
    private SweepMark? lastSweep;

    #endregion

    #region Actions - History

    private SessionEdit ClearingHistory(SessionState basis, ClearHistory intent) {
        IEnumerable<SpaceState> spaces = intent.SpaceId is { } spaceId ? [Editable(basis, spaceId)] : EditableSpaces(basis);
        return new(Replacing(basis, [.. spaces.Select(space => space.History.Count == 0 ? space : space with { History = [] })]),
            SyncStaging.Deletion);
    }

    private SessionEdit RemovingHistory(SessionState basis, RemoveHistoryAddress intent) {
        var space = Editable(basis, intent.SpaceId);
        var address = new WebAddress(intent.Address).Normalized;
        return new(Replacing(basis, WithoutHistory(space, entry => address is not null && entry.Url == address)), SyncStaging.Deletion);
    }

    private SessionEdit RemovingHistory(SessionState basis, RemoveHistoryRange intent) {
        var space = Editable(basis, intent.SpaceId);
        if (intent.End < intent.Start) throw new Rejected(new InvalidDateRange());
        var removed = RecordRemovalPolicy.WithinRange(Seconds(space.History.Select(entry => entry.LastVisitedAt)),
            StoredSessionCodec.Seconds(intent.Start), StoredSessionCodec.Seconds(intent.End)).ToHashSet();
        return new(Replacing(basis, WithoutHistory(space, (_, index) => removed.Contains(index))), SyncStaging.Deletion);
    }

    private static SpaceState WithoutHistory(SpaceState space, Func<HistoryEntryState, bool> removes) =>
        WithoutHistory(space, (entry, _) => removes(entry));

    private static SpaceState WithoutHistory(SpaceState space, Func<HistoryEntryState, int, bool> removes) {
        var kept = space.History.Where((entry, index) => !removes(entry, index)).ToArray();
        return kept.Length == space.History.Count ? space : space with { History = kept };
    }

    #endregion

    #region Actions - Retention

    /// Cleans up and applies retention in every Space not being deleted, or
    /// nothing when the last sweep covers this one.
    private SessionEdit? Sweeping(SessionState basis, DateTimeOffset now) {
        if (lastSweep?.Covers(now, basis) == true) return null;
        var kept = device?.ShownTabs(workspaceId);
        var swept = EditableSpaces(basis, maintains: true).Select(space => Expired(CleanedUp(space, now, kept), now)).ToArray();
        return new(Replacing(basis, swept), SyncStaging.Expiry, Sweep: new(now, SpaceRetention.Of(basis)));
    }

    private SessionEdit CleaningUp(SessionState basis, CleanUpCurrentTabs intent, DateTimeOffset now) {
        IEnumerable<SpaceState> spaces = intent.SpaceId is { } spaceId
            ? [Editable(basis, spaceId, maintains: true)] : EditableSpaces(basis, maintains: true);
        var kept = device?.ShownTabs(workspaceId);
        return new(Replacing(basis, [.. spaces.Select(space => CleanedUp(space, now, kept))]), SyncStaging.Expiry);
    }

    /// `space` with its open tabs unused for longer than its cleanup lifetime
    /// archived, keeping `kept`: the tabs windows show and saved windows will.
    private static SpaceState CleanedUp(SpaceState space, DateTimeOffset now, IReadOnlySet<Guid>? kept) {
        if (space.Settings.BrowsingPreferences.CurrentTabCleanup.Lifetime is not { } lifetime) return space;
        var edited = BrowserTabCollection.Restore(space);
        edited.CleanupCurrentTabs(null, lifetime, now, kept?.ToArray());
        return space.Tabs.SequenceEqual(edited.TabStates) ? space : edited.Capture(space);
    }

    /// `space` without the history and archive entries older than it keeps them.
    private static SpaceState Expired(SpaceState space, DateTimeOffset now) {
        var retention = space.Settings.BrowsingPreferences.DataRetention;
        var seconds = StoredSessionCodec.Seconds(now);
        if (retention.History.Lifetime is { } history) {
            var expired = RecordRemovalPolicy.Expired(Seconds(space.History.Select(entry => entry.LastVisitedAt)), seconds,
                history.TotalSeconds).ToHashSet();
            space = WithoutHistory(space, (_, index) => expired.Contains(index));
        }
        if (retention.Archive.Lifetime is { } archive) {
            var expired = RecordRemovalPolicy.Expired(Seconds(space.ArchivedTabs.Select(archived => archived.ArchivedAt)), seconds,
                archive.TotalSeconds).ToHashSet();
            if (expired.Count > 0) space = space with { ArchivedTabs = [.. space.ArchivedTabs.Where((_, index) => !expired.Contains(index))] };
        }
        return space;
    }

    #endregion

    #region Actions - Archive

    /// Reopens the archived tab as an open tab, which the issuing window shows.
    private SessionEdit Restoring(SessionState basis, RestoreArchivedTab intent, DateTimeOffset now) {
        var space = Editable(basis, intent.SpaceId);
        var index = space.ArchivedTabs.ToList().FindIndex(archived => archived.Tab.Id == intent.TabId);
        if (index < 0) throw new Rejected(new UnknownArchivedTab(intent.TabId));
        if (basis.Spaces.Any(candidate => candidate.Tabs.Any(tab => tab.Id == intent.TabId)))
            throw new Rejected(new TabAlreadyExists(intent.TabId));
        var remaining = space with { ArchivedTabs = [.. space.ArchivedTabs.Where((_, position) => position != index)] };
        var edited = BrowserTabCollection.Restore(remaining);
        var restored = edited.RestoreArchived(space.ArchivedTabs[index].Tab, now);
        var followUp = new WindowFollowUp(IssuingWindow(intent.WindowId)).ShowTab(space.Id, restored.Id);
        return new(Replacing(basis, edited.Capture(remaining)), SyncStaging.Creation, followUp);
    }

    #endregion

    #region Actions - Dates

    /// The dates as the stored format's seconds, which the removal policies read.
    private static double[] Seconds(IEnumerable<DateTimeOffset> dates) => dates.Select(StoredSessionCodec.Seconds).ToArray();

    #endregion
}
