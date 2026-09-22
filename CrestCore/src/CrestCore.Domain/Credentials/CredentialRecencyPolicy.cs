namespace CrestCore.Domain;

/// Which saved credential is the most recent: the latest use, or the latest
/// update for one never used, with the identity breaking exact ties so every
/// caller picks the same record.
public static class CredentialRecencyPolicy {
    #region Variables

    public const int MaximumRecords = 64;

    #endregion

    #region Actions - Recency

    public static bool IsLessRecent(CredentialRecord lhs, CredentialRecord rhs) {
        ArgumentNullException.ThrowIfNull(lhs);
        ArgumentNullException.ThrowIfNull(rhs);
        double left = Date(lhs.RecencyDate), right = Date(rhs.RecencyDate);
        if (left != right) return left < right;
        return string.CompareOrdinal(lhs.Id.ToString("D"), rhs.Id.ToString("D")) < 0;
    }

    /// Null when there are no records. Winners of separate batches reduce to
    /// the same answer as one batch, so callers may split long lists.
    public static CredentialRecord? MostRecent(IReadOnlyList<CredentialRecord> records) {
        ArgumentNullException.ThrowIfNull(records);
        if (records.Count > MaximumRecords) throw new BrowserRuleException(BrowserRuleCodes.CredentialRecordLimit);
        if (records.Select(record => record.Id).Distinct().Count() != records.Count)
            throw new BrowserRuleException(BrowserRuleCodes.DuplicateCredential);
        CredentialRecord? best = null;
        foreach (var record in records) {
            _ = Date(record.UpdatedAt);
            if (best is null || IsLessRecent(best, record)) best = record;
        }
        return best;
    }

    private static double Date(double value) =>
        double.IsFinite(value) ? value : throw new BrowserRuleException(BrowserRuleCodes.InvalidCredentialDate);

    #endregion
}
