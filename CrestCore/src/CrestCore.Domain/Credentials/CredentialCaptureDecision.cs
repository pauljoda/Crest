namespace CrestCore.Domain;

/// The capture policy's answer for one observation. `ClearsUsernameHint` asks
/// the caller to forget a remembered username that no longer applies.
/// `AnchorsToField` says whether a fill prompt may point at the reported field.
public sealed record CredentialCaptureDecision(CredentialCaptureAction Action,
    CredentialUsernameSource UsernameSource = CredentialUsernameSource.None, bool ClearsUsernameHint = false,
    bool IsCrossOriginFrame = false, bool AnchorsToField = false);
