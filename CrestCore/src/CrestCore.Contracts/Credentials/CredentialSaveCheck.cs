namespace CrestCore.Contracts;

/// Whether a save candidate submitted at `SubmittedAt` may still be planned or
/// committed at `Now`. Both are in seconds since 1970.
public sealed record CredentialSaveCheck(CredentialOrigin Origin, CredentialOrigin TopLevelOrigin, double SubmittedAt,
    double Now) : Query<CredentialSaveVerdict>;
