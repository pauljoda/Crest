using CrestCore.Contracts;

namespace CrestCore.Domain;

public static class HistoryPolicy {
    #region Variables

    public const int MaximumEntries = 5000;

    #endregion

    #region Actions - Navigation

    /// A newest-first history after a visit to `url`, capped at
    /// `MaximumEntries`: the page's entry, with one more visit, goes first, and
    /// a new entry takes `newId`. Null for an address history does not keep,
    /// which leaves it as it was.
    public static IReadOnlyList<HistoryEntryState>? Visit(IReadOnlyList<HistoryEntryState> history, string url, string? title,
        DateTimeOffset now, Guid newId) {
        ArgumentNullException.ThrowIfNull(history);
        if (new WebAddress(url).Normalized is not { } normalized) return null;
        var visit = Record(normalized, title, now, newId, history.FirstOrDefault(entry => entry.Url == normalized));
        return [.. new[] { visit }.Concat(history.Where(entry => entry.Id != visit.Id)).Take(MaximumEntries)];
    }

    public static HistoryEntryState Record(string normalizedUrl, string? title, DateTimeOffset now, Guid newId, HistoryEntryState? previous) {
        if (new WebAddress(normalizedUrl).Normalized != normalizedUrl || newId == Guid.Empty
            || previous is not null && previous.Url != normalizedUrl) throw new BrowserRuleException(BrowserRuleCodes.InvalidHistoryVisit);
        string resolvedTitle = string.IsNullOrEmpty(title) ? new Uri(normalizedUrl).Host : title;
        if (resolvedTitle.Length == 0) resolvedTitle = normalizedUrl;
        return previous is null ? new(newId, normalizedUrl, resolvedTitle, now, now, 1)
            : previous with { Title = resolvedTitle, LastVisitedAt = now, VisitCount = checked(previous.VisitCount + 1) };
    }

    #endregion
}
