namespace CrestCore.Contracts;

/// The capture rules' answer for one observation. `ClearsUsernameHint` asks
/// the caller to forget a remembered username that no longer applies.
/// `AnchorsToField` says whether a fill prompt may point at the reported field.
/// `CandidateLifetime` and `UsernameHintLifetime` are the seconds a captured
/// candidate and a remembered username stay usable. `Form` is how the core
/// read the form: the fields a fill writes into and a capture reads from.
/// `PasswordKind` says whether a fill offers saved logins or a new password,
/// and which kind of password a capture keeps. `QuietWithoutLogins` says the
/// prompt shows only when logins are saved.
public sealed record CredentialCaptureDecision(CredentialCaptureAction Action, CredentialUsernameSource UsernameSource,
    bool ClearsUsernameHint, bool IsCrossOriginFrame, bool AnchorsToField, double CandidateLifetime,
    double UsernameHintLifetime, SignInForm Form, CredentialPasswordKind? PasswordKind, bool QuietWithoutLogins) {
    #region Actions - Capture

    /// A decision carrying the lifetimes the caller schedules expiry with.
    internal static CredentialCaptureDecision For(CredentialCaptureAction action,
        CredentialUsernameSource usernameSource = CredentialUsernameSource.None, bool clearsUsernameHint = false,
        bool isCrossOriginFrame = false, bool anchorsToField = false, SignInForm? form = null,
        CredentialPasswordKind? passwordKind = null, bool quietWithoutLogins = false) =>
        new(action, usernameSource, clearsUsernameHint, isCrossOriginFrame, anchorsToField, CredentialPendingCandidate.Lifetime,
            CredentialUsernameHint.Lifetime, form ?? SignInForm.Quiet, passwordKind, quietWithoutLogins);

    #endregion
}
