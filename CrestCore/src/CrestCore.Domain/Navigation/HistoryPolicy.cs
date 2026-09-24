using CrestCore.Contracts;

namespace CrestCore.Domain;

public static class HistoryPolicy {
    #region Variables

    public const int MaximumEntries = 5000;

    #endregion

    #region Actions - Navigation

    public static string? Normalize(string url) {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var value)
            || value.Scheme != Uri.UriSchemeHttp && value.Scheme != Uri.UriSchemeHttps) return null;
        return url.Split('#', 2)[0];
    }

    /// Two spellings of one address are one page. Everything that asks "is this
    /// still the page I captured?" — an automatic favicon, a saved location —
    /// asks it here, so a fragment or an unnormalizable scheme cannot make the
    /// same page look like two.
    public static bool SamePage(string? left, string? right) {
        if (left is null || right is null) return left is null && right is null;
        return (Normalize(left) ?? left) == (Normalize(right) ?? right);
    }

    /// A newest-first history after a visit to `url`, capped at
    /// `MaximumEntries`: the page's entry, with one more visit, goes first, and
    /// a new entry takes `newId`. Null for an address history does not keep,
    /// which leaves it as it was.
    public static IReadOnlyList<HistoryEntryState>? Visit(IReadOnlyList<HistoryEntryState> history, string url, string? title,
        DateTimeOffset now, Guid newId) {
        ArgumentNullException.ThrowIfNull(history);
        if (Normalize(url) is not { } normalized) return null;
        var visit = Record(normalized, title, now, newId, history.FirstOrDefault(entry => entry.Url == normalized));
        return [.. new[] { visit }.Concat(history.Where(entry => entry.Id != visit.Id)).Take(MaximumEntries)];
    }

    public static HistoryEntryState Record(string normalizedUrl, string? title, DateTimeOffset now, Guid newId, HistoryEntryState? previous) {
        if (Normalize(normalizedUrl) != normalizedUrl || newId == Guid.Empty
            || previous is not null && previous.Url != normalizedUrl) throw new BrowserRuleException(BrowserRuleCodes.InvalidHistoryVisit);
        string resolvedTitle = string.IsNullOrEmpty(title) ? new Uri(normalizedUrl).Host : title;
        if (resolvedTitle.Length == 0) resolvedTitle = normalizedUrl;
        return previous is null ? new(newId, normalizedUrl, resolvedTitle, now, now, 1)
            : previous with { Title = resolvedTitle, LastVisitedAt = now, VisitCount = checked(previous.VisitCount + 1) };
    }

    #endregion
}
