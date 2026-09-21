namespace CrestCore.Domain;

public static class HistoryPolicy {
    #region Variables

    public const int MaximumEntries = 5000;

    #endregion

    #region Actions - Navigation

    public static string? Normalize(string url) {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var value) || value.Scheme is not ("http" or "https")) return null;
        return url.Split('#', 2)[0];
    }

    public static HistoryVisit Record(string normalizedUrl, string? title, DateTimeOffset now, Guid newId, HistoryVisit? previous) {
        if (Normalize(normalizedUrl) != normalizedUrl || newId == Guid.Empty
            || previous is not null && previous.Url != normalizedUrl) throw new BrowserRuleException("invalid_history_visit");
        string resolvedTitle = string.IsNullOrEmpty(title) ? new Uri(normalizedUrl).Host : title;
        if (resolvedTitle.Length == 0) resolvedTitle = normalizedUrl;
        return previous is null ? new(newId, normalizedUrl, resolvedTitle, now, now, 1)
            : previous with { Title = resolvedTitle, VisitedAt = now, VisitCount = checked(previous.VisitCount + 1) };
    }

    #endregion
}
