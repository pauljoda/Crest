namespace CrestCore.Contracts;

/// Whether a fill may go ahead.
public sealed record CredentialFillDecision(bool IsAllowed);
