namespace CrestCore.Contracts;

/// Whether a save candidate is still accepted, or why it is not.
public sealed record CredentialSaveVerdict(CredentialSaveValidity Validity);
