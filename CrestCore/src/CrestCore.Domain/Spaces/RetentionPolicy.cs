using CrestCore.Contracts;

namespace CrestCore.Domain;

/// How long a Space keeps open tabs nobody uses, and its history and archive.
public static class RetentionPolicy {
    #region Actions - Retention

    /// How long an open tab may go unused; null keeps it.
    public static TimeSpan? TabLifetime(CurrentTabCleanup cleanup) => cleanup switch {
        CurrentTabCleanup.After12Hours => TimeSpan.FromHours(12),
        CurrentTabCleanup.After24Hours => TimeSpan.FromDays(1),
        CurrentTabCleanup.After7Days => TimeSpan.FromDays(7),
        CurrentTabCleanup.After30Days => TimeSpan.FromDays(30),
        _ => null
    };

    /// How long a record is kept; null keeps it forever.
    public static TimeSpan? Lifetime(DataRetention duration) => duration switch {
        DataRetention.OneDay => TimeSpan.FromDays(1),
        DataRetention.OneWeek => TimeSpan.FromDays(7),
        DataRetention.ThirtyDays => TimeSpan.FromDays(30),
        DataRetention.NinetyDays => TimeSpan.FromDays(90),
        DataRetention.OneYear => TimeSpan.FromDays(365),
        _ => null
    };

    #endregion
}
