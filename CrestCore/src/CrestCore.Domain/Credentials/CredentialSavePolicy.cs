using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Whether a submitted credential creates a record, updates the most recent
/// record for the same account, or is already stored. Accounts match by
/// username without regard to case. The stored secret stays with the platform:
/// it compares the candidate against the matched record and reports only
/// whether the passwords are equal.
public static class CredentialSavePolicy {
    #region Variables

    public const int MaximumUsernameLength = 4_096;

    #endregion

    #region Actions - Saving

    /// The most recent record whose username names the same account, or null.
    /// Usernames are compared after canonical composition, ignoring case; a
    /// record without a username is refused, and an empty one never matches.
    public static CredentialRecord? Match(string username, IReadOnlyList<CredentialRecord> records) {
        ArgumentNullException.ThrowIfNull(username);
        ArgumentNullException.ThrowIfNull(records);
        if (username.Length is 0 or > MaximumUsernameLength) throw new Rejected(new InvalidCredentialUsername());
        if (records.Count > CredentialRecencyPolicy.MaximumRecords)
            throw new Rejected(new CredentialRecordLimitReached(CredentialRecencyPolicy.MaximumRecords));
        if (records.Any(record => record.Username is null)) throw new Rejected(new InvalidCredentialRecord());
        if (records.Any(record => record.Username!.Length > MaximumUsernameLength)) throw new Rejected(new InvalidCredentialUsername());
        string account = Account(username);
        return CredentialRecencyPolicy.MostRecent(records
            .Where(record => string.Equals(Account(record.Username!), account, StringComparison.OrdinalIgnoreCase))
            .ToArray());
    }

    /// `matchId` is the record `Match` chose. `stored` is null when there was
    /// no match or its secret could not be read; either way the save creates a
    /// record. A comparison for another record is stale and refused.
    public static CredentialSavePlan Plan(Guid? matchId, CredentialStoredComparison? stored) {
        if (stored is not null && stored.Id != matchId) throw new Rejected(new StaleCredentialComparison());
        if (matchId is null || stored is null) return new(CredentialSavePlanKind.Create, null);
        return new(stored.PasswordMatches ? CredentialSavePlanKind.AlreadyStored : CredentialSavePlanKind.Update, matchId);
    }

    private static string Account(string username) => username.Normalize(NormalizationForm.FormC);

    #endregion
}
