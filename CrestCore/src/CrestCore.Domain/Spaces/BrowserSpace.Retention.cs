namespace CrestCore.Domain;

public sealed partial class BrowserSpace {
    #region Variables

    public RetentionPreferences Retention { get; private set; } = RetentionPreferences.Default;

    #endregion

    #region Actions - Retention

    public IReadOnlyList<BrowserTab> ExpiredTabs(DateTimeOffset now, IReadOnlySet<TabId> protectedTabs) {
        if (IsLocked || Retention.TabLifetime is not { } lifetime) return [];
        return tabs.Where(t => t.Placement == TabPlacement.Current && !t.Content.IsStartPage
            && t.Phase is not (TabPhase.Creating or TabPhase.Closing or TabPhase.Unloading) && !protectedTabs.Contains(t.Id)
            && now - t.LastActivatedAt > lifetime).ToArray();
    }
    public bool PruneStoredRecords(DateTimeOffset now) {
        int removed = 0;
        if (RetentionPreferences.Lifetime(Retention.History) is { } historyLifetime) {
            var indices = RecordRemovalPolicy.Expired(history.Select(h => (h.VisitedAt - DateTimeOffset.UnixEpoch).TotalSeconds).ToArray(),
                (now - DateTimeOffset.UnixEpoch).TotalSeconds, historyLifetime.TotalSeconds);
            foreach (var index in indices.Reverse()) history.RemoveAt(index);
            removed += indices.Count;
        }
        if (RetentionPreferences.Lifetime(Retention.Archive) is { } archiveLifetime) {
            var indices = RecordRemovalPolicy.Expired(archive.Select(a => (a.ClosedAt - DateTimeOffset.UnixEpoch).TotalSeconds).ToArray(),
                (now - DateTimeOffset.UnixEpoch).TotalSeconds, archiveLifetime.TotalSeconds);
            foreach (var index in indices.Reverse()) archive.RemoveAt(index);
            removed += indices.Count;
        }
        return removed > 0;
    }

    #endregion

    #region Mutators

    public void SetRetention(RetentionPreferences value) { EnsureAccessible(); value.Validate(); Retention = value; }

    #endregion
}
