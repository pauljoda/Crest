namespace CrestCore.Contracts;

/// A credential date or clock reading is not finite.
public sealed record InvalidCredentialDate() : Rejection;
