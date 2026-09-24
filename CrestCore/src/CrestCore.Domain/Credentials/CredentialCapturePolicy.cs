using CrestCore.Contracts;

namespace CrestCore.Domain;

/// When a page's credential form observations become fill offers, save
/// candidates and save prompts. Credentials are only captured and offered
/// where both the frame and its top-level page are secure.
public static class CredentialCapturePolicy {
    #region Variables

    /// Seconds a submitted credential waits for the page to show it signed in.
    public const double CandidateLifetime = 45;

    /// Seconds a username from one login step is kept for the next step.
    public const double UsernameHintLifetime = 5 * 60;

    #endregion

    #region Actions - Capture

    public static bool Accepts(CredentialOrigin frameOrigin, CredentialOrigin topLevelOrigin) =>
        Valid(frameOrigin).IsSecure && Valid(topLevelOrigin).IsSecure;

    /// Saved credentials are offered to current-password fields; generated
    /// passwords only to new-password fields.
    public static bool Offers(CredentialFillSource source, CredentialPasswordKind passwordKind) => source switch {
        CredentialFillSource.Saved => passwordKind == CredentialPasswordKind.Current,
        _ => passwordKind == CredentialPasswordKind.New
    };

    /// A candidate is current from its submission until its lifetime ends. A
    /// candidate from the future is never current.
    public static bool IsCurrent(double submittedAt, double now) {
        double age = Seconds(now) - Seconds(submittedAt);
        return age is >= 0 and <= CandidateLifetime;
    }

    public static bool ShouldOfferSave(double submittedAt, bool hasVisiblePasswordField, double now) =>
        IsCurrent(submittedAt, now) && !hasVisiblePasswordField;

    /// A remembered username applies only to the exact frame and top-level
    /// origins that produced it, and only within its lifetime.
    public static bool HintApplies(CredentialUsernameHint hint, CredentialOrigin frameOrigin,
        CredentialOrigin topLevelOrigin, double now) {
        ArgumentNullException.ThrowIfNull(hint);
        return Valid(hint.Origin) == frameOrigin && Valid(hint.TopLevelOrigin) == topLevelOrigin
            && Seconds(now) - Seconds(hint.CapturedAt) <= UsernameHintLifetime;
    }

    public static CredentialSaveValidity SaveValidity(CredentialOrigin origin, CredentialOrigin topLevelOrigin,
        double submittedAt, double now) {
        if (!Accepts(origin, topLevelOrigin)) return CredentialSaveValidity.InsecureOrigin;
        return IsCurrent(submittedAt, now) ? CredentialSaveValidity.Accepted : CredentialSaveValidity.Stale;
    }

    public static CredentialCaptureDecision Decide(CredentialFormFacts facts, CredentialUsernameHint? hint,
        CredentialPendingCandidate? pending, double now) {
        ArgumentNullException.ThrowIfNull(facts);
        bool accepted = Accepts(facts.FrameOrigin, facts.TopLevelOrigin);
        bool crossOrigin = facts.FrameOrigin != facts.TopLevelOrigin;
        switch (facts.Event) {
            case CredentialCaptureEvent.Username:
            case CredentialCaptureEvent.Filled:
                return Decision(accepted && facts.HasUsername ? CredentialCaptureAction.RememberUsername : CredentialCaptureAction.Ignore);
            case CredentialCaptureEvent.Focus: {
                    if (facts.PasswordKind is null) return Decision(CredentialCaptureAction.DismissFill);
                    if (!accepted || !facts.HasFormId || !facts.HasFillTarget) return Decision(CredentialCaptureAction.Ignore);
                    var source = Username(facts, hint, now);
                    return Decision(CredentialCaptureAction.OfferFill, source, source == CredentialUsernameSource.None,
                        crossOrigin, facts.IsMainFrame);
                }
            case CredentialCaptureEvent.Submit: {
                    if (!accepted) return Decision(CredentialCaptureAction.Ignore);
                    var source = Username(facts, hint, now);
                    if (source == CredentialUsernameSource.None) return Decision(CredentialCaptureAction.Ignore, clearsUsernameHint: true);
                    if (!facts.HasPassword || facts.PasswordKind is null) return Decision(CredentialCaptureAction.Ignore);
                    return Decision(CredentialCaptureAction.CaptureCandidate, source, isCrossOriginFrame: crossOrigin);
                }
            default: {
                    if (pending is null || facts.HasVisiblePasswordField is not { } visible
                        || !facts.IsMainFrame && facts.FrameOrigin != Valid(pending.Origin)) return Decision(CredentialCaptureAction.Ignore);
                    if (ShouldOfferSave(pending.SubmittedAt, visible, now)) return Decision(CredentialCaptureAction.OfferSave);
                    return Decision(Seconds(now) - Seconds(pending.SubmittedAt) > CandidateLifetime
                        ? CredentialCaptureAction.DiscardPending : CredentialCaptureAction.KeepPending);
                }
        }
    }

    /// A decision carrying the lifetimes the caller schedules expiry with.
    public static CredentialCaptureDecision Decision(CredentialCaptureAction action,
        CredentialUsernameSource usernameSource = CredentialUsernameSource.None, bool clearsUsernameHint = false,
        bool isCrossOriginFrame = false, bool anchorsToField = false) =>
        new(action, usernameSource, clearsUsernameHint, isCrossOriginFrame, anchorsToField, CandidateLifetime,
            UsernameHintLifetime);

    /// An explicit username wins; otherwise a remembered one that still applies.
    private static CredentialUsernameSource Username(CredentialFormFacts facts, CredentialUsernameHint? hint, double now) {
        if (facts.HasUsername) return CredentialUsernameSource.Explicit;
        return hint is not null && HintApplies(hint, facts.FrameOrigin, facts.TopLevelOrigin, now)
            ? CredentialUsernameSource.Hint : CredentialUsernameSource.None;
    }

    private static CredentialOrigin Valid(CredentialOrigin origin) {
        ArgumentNullException.ThrowIfNull(origin);
        return origin.IsValid ? origin : throw new Rejected(new InvalidCredentialOrigin());
    }

    private static double Seconds(double value) =>
        double.IsFinite(value) ? value : throw new Rejected(new InvalidCredentialDate());

    #endregion
}
