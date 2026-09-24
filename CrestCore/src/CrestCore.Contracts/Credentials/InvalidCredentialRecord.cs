namespace CrestCore.Contracts;

/// A record an account match needs has no username.
public sealed record InvalidCredentialRecord() : Rejection;
