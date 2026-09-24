namespace CrestCore.Contracts;

/// A credential origin is not a canonical HTTP(S) origin.
public sealed record InvalidCredentialOrigin() : Rejection;
