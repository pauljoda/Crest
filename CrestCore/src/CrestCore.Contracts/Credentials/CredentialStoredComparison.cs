namespace CrestCore.Contracts;

/// The platform's comparison of a candidate against the stored secret of the
/// matched record. The core never receives either password, only this answer.
public sealed record CredentialStoredComparison(Guid Id, bool PasswordMatches);
