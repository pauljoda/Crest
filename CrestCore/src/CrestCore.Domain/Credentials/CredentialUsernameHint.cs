namespace CrestCore.Domain;

/// The page's remembered username from an earlier step of a multi-step login,
/// without the username itself. `CapturedAt` is in seconds since 1970.
public sealed record CredentialUsernameHint(CredentialOrigin Origin, CredentialOrigin TopLevelOrigin, double CapturedAt);
