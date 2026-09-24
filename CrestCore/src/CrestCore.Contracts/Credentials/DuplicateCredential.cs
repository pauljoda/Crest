namespace CrestCore.Contracts;

/// Two records in one question share an identity.
public sealed record DuplicateCredential() : Rejection;
