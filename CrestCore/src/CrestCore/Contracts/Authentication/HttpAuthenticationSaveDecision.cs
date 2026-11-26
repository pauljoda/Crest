namespace CrestCore.Contracts;

/// Whether a submitted HTTP authentication prompt should queue a save once the
/// server accepts it, and whether that save replaces a previously rejected
/// stored credential.
public sealed record HttpAuthenticationSaveDecision(
    bool ShouldSave,
    bool ReplacesRejectedCredential);
