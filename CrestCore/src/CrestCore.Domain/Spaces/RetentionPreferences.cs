namespace CrestCore.Domain;

public sealed record RetentionPreferences(CurrentTabCleanup CurrentTabs, DataRetention History,
    DataRetention Archive, DataRetention Downloads) {
    public static RetentionPreferences Default { get; } = new(CurrentTabCleanup.After12Hours,
        DataRetention.Forever, DataRetention.Forever, DataRetention.Forever);
    public TimeSpan? TabLifetime => CurrentTabs switch {
        CurrentTabCleanup.After12Hours => TimeSpan.FromHours(12),
        CurrentTabCleanup.After24Hours => TimeSpan.FromDays(1),
        CurrentTabCleanup.After7Days => TimeSpan.FromDays(7),
        CurrentTabCleanup.After30Days => TimeSpan.FromDays(30),
        _ => null
    };
    public static TimeSpan? Lifetime(DataRetention duration) => duration switch {
        DataRetention.OneDay => TimeSpan.FromDays(1),
        DataRetention.OneWeek => TimeSpan.FromDays(7),
        DataRetention.ThirtyDays => TimeSpan.FromDays(30),
        DataRetention.NinetyDays => TimeSpan.FromDays(90),
        DataRetention.OneYear => TimeSpan.FromDays(365),
        _ => null
    };
    public void Validate() {
        if (!Enum.IsDefined(CurrentTabs) || !Enum.IsDefined(History) || !Enum.IsDefined(Archive) || !Enum.IsDefined(Downloads))
            throw new BrowserRuleException("invalid_retention");
    }
}
