using CrestCore.Application;

namespace CrestCore.Contracts;

/// Plans how Crest answers one HTTP Basic/Digest password challenge without
/// carrying any password across the boundary. A stored credential is tried once
/// on a secure origin before prompting; any failure marks a matching attempted
/// credential as rejected and suggests its username unless the challenge
/// already proposed one.
public sealed record HttpAuthenticationChallengePlan(
    bool AllowsCredentialSaving,
    bool IsSecureOrigin,
    int PreviousFailureCount,
    bool HasStoredCredential,
    bool AttemptedSameProtectionSpace,
    string? ProposedUsername,
    string? AttemptedUsername) : StandaloneQuery<HttpAuthenticationDecision> {
    #region Actions - Answering

    internal override HttpAuthenticationDecision Answer(StandaloneContext context) {
        var rejected = PreviousFailureCount > 0 && AttemptedSameProtectionSpace;
        var usesStored = AllowsCredentialSaving && PreviousFailureCount == 0 && IsSecureOrigin && HasStoredCredential;
        var allowsSaving = AllowsCredentialSaving && IsSecureOrigin;
        var suggestedUsername = ProposedUsername ?? (rejected ? AttemptedUsername : null);
        return new(usesStored, rejected, allowsSaving, suggestedUsername);
    }

    #endregion
}
