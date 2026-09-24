namespace CrestCore.Contracts;

/// The record a credential rule chose, or null when none qualifies.
public sealed record CredentialChoice(Guid? CredentialId);
