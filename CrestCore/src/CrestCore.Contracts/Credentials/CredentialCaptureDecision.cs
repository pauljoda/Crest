namespace CrestCore.Contracts;

/// The capture policy's answer for one observation. `ClearsUsernameHint` asks
/// the caller to forget a remembered username that no longer applies.
/// `AnchorsToField` says whether a fill prompt may point at the reported field.
/// `CandidateLifetime` and `UsernameHintLifetime` are the seconds a captured
/// candidate and a remembered username stay usable.
public sealed record CredentialCaptureDecision(CredentialCaptureAction Action, CredentialUsernameSource UsernameSource,
    bool ClearsUsernameHint, bool IsCrossOriginFrame, bool AnchorsToField, double CandidateLifetime,
    double UsernameHintLifetime);
