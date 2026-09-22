namespace CrestCore.Domain;

/// What one validated form message says, without its credential material. The
/// platform keeps the username and password values; the core only learns
/// whether they are present.
public sealed record CredentialFormFacts(CredentialCaptureEvent Event, CredentialOrigin FrameOrigin,
    CredentialOrigin TopLevelOrigin, bool IsMainFrame, bool HasFormId, bool HasUsername, bool HasPassword,
    CredentialPasswordKind? PasswordKind, bool? HasVisiblePasswordField, bool HasFillTarget);
