namespace CrestCore.Domain;

/// Numeric timestamps keep native Date precision at a retention boundary.
/// Callers apply the returned indices to their existing value snapshots.
public static class RecordRemovalPolicy
{
    public static IReadOnlyList<int> Expired(IReadOnlyList<double> timestamps, double now, double lifetime)
    {
        Validate(timestamps);
        if (!double.IsFinite(now) || !double.IsFinite(lifetime) || lifetime < 0)
            throw new BrowserRuleException("invalid_retention_interval");
        return Enumerable.Range(0, timestamps.Count).Where(i => now - timestamps[i] > lifetime).ToArray();
    }

    public static IReadOnlyList<int> WithinRange(IReadOnlyList<double> timestamps, double start, double end)
    {
        Validate(timestamps);
        if (!double.IsFinite(start) || !double.IsFinite(end)) throw new BrowserRuleException("invalid_history_range");
        return Enumerable.Range(0, timestamps.Count).Where(i => timestamps[i] >= start && timestamps[i] < end).ToArray();
    }

    private static void Validate(IReadOnlyList<double> timestamps)
    {
        if (timestamps.Any(value => !double.IsFinite(value))) throw new BrowserRuleException("invalid_record_date");
    }
}
