namespace CrestCore.Domain;

public enum CurrentTabCleanup { After12Hours, After24Hours, After7Days, After30Days, Never }
public enum DataRetention { OneDay, OneWeek, ThirtyDays, NinetyDays, OneYear, Forever }
public sealed record RetentionPreferences(CurrentTabCleanup CurrentTabs, DataRetention History,
    DataRetention Archive, DataRetention Downloads)
{
    public static RetentionPreferences Default { get; } = new(CurrentTabCleanup.After12Hours,
        DataRetention.Forever, DataRetention.Forever, DataRetention.Forever);
    public TimeSpan? TabLifetime => CurrentTabs switch
    {
        CurrentTabCleanup.After12Hours => TimeSpan.FromHours(12), CurrentTabCleanup.After24Hours => TimeSpan.FromDays(1),
        CurrentTabCleanup.After7Days => TimeSpan.FromDays(7), CurrentTabCleanup.After30Days => TimeSpan.FromDays(30), _ => null
    };
    public static TimeSpan? Lifetime(DataRetention duration) => duration switch
    {
        DataRetention.OneDay => TimeSpan.FromDays(1), DataRetention.OneWeek => TimeSpan.FromDays(7),
        DataRetention.ThirtyDays => TimeSpan.FromDays(30), DataRetention.NinetyDays => TimeSpan.FromDays(90),
        DataRetention.OneYear => TimeSpan.FromDays(365), _ => null
    };
    public void Validate()
    {
        if (!Enum.IsDefined(CurrentTabs) || !Enum.IsDefined(History) || !Enum.IsDefined(Archive) || !Enum.IsDefined(Downloads))
            throw new BrowserRuleException("invalid_retention");
    }
}

public sealed partial class BrowserSpace
{
    public RetentionPreferences Retention { get; private set; } = RetentionPreferences.Default;
    public void SetRetention(RetentionPreferences value) { EnsureAccessible(); value.Validate(); Retention = value; }
    public IReadOnlyList<BrowserTab> ExpiredTabs(DateTimeOffset now, IReadOnlySet<TabId> protectedTabs)
    {
        if (IsLocked || Retention.TabLifetime is not { } lifetime) return [];
        return tabs.Where(t => t.Placement == TabPlacement.Current && t.Kind != TabKind.StartPage
            && t.Phase is not (TabPhase.Creating or TabPhase.Closing or TabPhase.Unloading) && !protectedTabs.Contains(t.Id)
            && now - t.LastActivatedAt > lifetime).ToArray();
    }
    public bool PruneStoredRecords(DateTimeOffset now)
    {
        int removed = 0;
        if (RetentionPreferences.Lifetime(Retention.History) is { } historyLifetime)
        {
            var indices = RecordRemovalPolicy.Expired(history.Select(h => (h.VisitedAt - DateTimeOffset.UnixEpoch).TotalSeconds).ToArray(),
                (now - DateTimeOffset.UnixEpoch).TotalSeconds, historyLifetime.TotalSeconds);
            foreach (var index in indices.Reverse()) history.RemoveAt(index);
            removed += indices.Count;
        }
        if (RetentionPreferences.Lifetime(Retention.Archive) is { } archiveLifetime)
        {
            var indices = RecordRemovalPolicy.Expired(archive.Select(a => (a.ClosedAt - DateTimeOffset.UnixEpoch).TotalSeconds).ToArray(),
                (now - DateTimeOffset.UnixEpoch).TotalSeconds, archiveLifetime.TotalSeconds);
            foreach (var index in indices.Reverse()) archive.RemoveAt(index);
            removed += indices.Count;
        }
        return removed > 0;
    }
}
