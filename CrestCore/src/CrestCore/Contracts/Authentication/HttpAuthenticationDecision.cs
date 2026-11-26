namespace CrestCore.Contracts;

/// What a page's HTTP authentication session does for one password challenge:
/// whether it answers with a stored credential, whether an earlier stored
/// attempt was rejected, whether the prompt may offer saving, and which
/// username the prompt suggests.
public sealed record HttpAuthenticationDecision(
    bool UsesStoredCredential,
    bool StoredCredentialRejected,
    bool AllowsSaving,
    string? SuggestedUsername);
