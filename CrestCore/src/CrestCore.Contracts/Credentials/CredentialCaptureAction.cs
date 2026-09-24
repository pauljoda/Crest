namespace CrestCore.Contracts;

/// What the page's credential state does with one observation.
public enum CredentialCaptureAction {
    Ignore,
    RememberUsername,
    DismissFill,
    OfferFill,
    CaptureCandidate,
    OfferSave,
    KeepPending,
    DiscardPending
}
