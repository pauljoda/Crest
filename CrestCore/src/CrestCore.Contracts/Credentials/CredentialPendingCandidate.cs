namespace CrestCore.Contracts;

/// A submitted credential still waiting for the page to show it signed in.
/// `SubmittedAt` is in seconds since 1970.
public sealed record CredentialPendingCandidate(CredentialOrigin Origin, double SubmittedAt);
