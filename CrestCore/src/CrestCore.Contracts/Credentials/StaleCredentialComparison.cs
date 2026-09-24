namespace CrestCore.Contracts;

/// The platform compared the candidate against a record other than the match.
public sealed record StaleCredentialComparison() : Rejection;
