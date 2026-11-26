using CrestCore.Application;

namespace CrestCore.Contracts;

/// Decides whether an HTTP authentication response submitted by the person
/// should be saved once the server accepts it, and whether it replaces a
/// previously rejected credential for the same account.
public sealed record HttpAuthenticationSavePlan(
    bool AllowsCredentialSaving,
    bool IsSecureOrigin,
    bool UserRequestedSave,
    string SubmittedUsername,
    string? RejectedUsername) : StandaloneQuery<HttpAuthenticationSaveDecision> {
    #region Actions - Answering

    internal override HttpAuthenticationSaveDecision Answer(StandaloneContext context) {
        var shouldSave = AllowsCredentialSaving && UserRequestedSave && IsSecureOrigin;
        var replaces = shouldSave && RejectedUsername is not null && RejectedUsername == SubmittedUsername;
        return new(shouldSave, replaces);
    }

    #endregion
}
