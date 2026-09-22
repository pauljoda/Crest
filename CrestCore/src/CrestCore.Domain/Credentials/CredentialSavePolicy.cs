using System.Text;

namespace CrestCore.Domain;

/// Whether a submitted credential creates a record, updates the most recent
/// record for the same account, or is already stored. Accounts match by
/// username without regard to case. The stored secret stays with the platform:
/// it compares the candidate against the matched record and reports only
/// whether the passwords are equal.
public static class CredentialSavePolicy {
    #region Actions - Saving

    /// The most recent record whose username names the same account, or null.
    /// Usernames are compared after canonical composition, ignoring case; a
    /// record without a username never matches.
    public static CredentialRecord? Match(string username, IReadOnlyList<CredentialRecord> records) {
        ArgumentException.ThrowIfNullOrEmpty(username);
        ArgumentNullException.ThrowIfNull(records);
        if (records.Any(record => record.Username is null))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidCredentialRecord);
        string account = Account(username);
        return CredentialRecencyPolicy.MostRecent(records
            .Where(record => string.Equals(Account(record.Username!), account, StringComparison.OrdinalIgnoreCase))
            .ToArray());
    }

    /// `matchId` is the record `Match` chose. `stored` is null when there was
    /// no match or its secret could not be read; either way the save creates a
    /// record. A comparison for another record is stale and rejected.
    public static CredentialSavePlan Plan(Guid? matchId, CredentialStoredComparison? stored) {
        if (stored is not null && stored.Id != matchId) throw new BrowserRuleException(BrowserRuleCodes.StaleCredentialComparison);
        if (matchId is null || stored is null) return new(CredentialSavePlanKind.Create, null);
        return new(stored.PasswordMatches ? CredentialSavePlanKind.AlreadyStored : CredentialSavePlanKind.Update, matchId);
    }

    private static string Account(string username) => username.Normalize(NormalizationForm.FormC);

    #endregion
}
