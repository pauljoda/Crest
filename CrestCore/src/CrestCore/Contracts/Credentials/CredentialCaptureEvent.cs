namespace CrestCore.Contracts;

/// A credential form observation: a focused field, a sent form with a password
/// field (`Submit`) or without one (`Username`), the page's password fields
/// coming and going, or `Filled` when the native layer finished filling a
/// saved credential into the page. Each event decides what it means for the
/// page's credential state: credentials are only captured and offered where
/// both the frame and its top-level page are secure. An event travels as its
/// index in `All`, so `All` is append-only.
public sealed class CredentialCaptureEvent {
    #region Static Variables

    public static readonly CredentialCaptureEvent Username = new(name: "username", decide: Sent);
    public static readonly CredentialCaptureEvent Focus = new(name: "focus", decide: Focused);
    public static readonly CredentialCaptureEvent Submit = new(name: "submit", decide: Sent);
    public static readonly CredentialCaptureEvent DocumentState = new(name: "documentState", decide: (facts, _, _, pending, now) => {
        if (pending is null || facts.HasVisiblePasswordField is not { } visible
            || !facts.IsMainFrame && facts.FrameOrigin != pending.Origin.Validated())
            return CredentialCaptureDecision.For(CredentialCaptureAction.Ignore);
        if (pending.OffersSave(visible, now))
            return CredentialCaptureDecision.For(CredentialCaptureAction.OfferSave);
        return CredentialCaptureDecision.For(
            pending.Age(now) > CredentialPendingCandidate.Lifetime
                ? CredentialCaptureAction.DiscardPending : CredentialCaptureAction.KeepPending);
    });
    public static readonly CredentialCaptureEvent Filled = new(name: "filled", decide: (facts, accepted, _, _, _) =>
        CredentialCaptureDecision.For(accepted && facts.FilledUsername ? CredentialCaptureAction.RememberUsername : CredentialCaptureAction.Ignore));

    public static IReadOnlyList<CredentialCaptureEvent> All { get; } = [Username, Focus, Submit, DocumentState, Filled];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the observation means, given its facts, whether its frame and
    /// top-level page are secure, the page's remembered username, its pending
    /// candidate and the time now.
    private readonly Func<CredentialFormFacts, bool, CredentialUsernameHint?, CredentialPendingCandidate?, double,
        CredentialCaptureDecision> decide;

    #endregion

    #region Constructors

    private CredentialCaptureEvent(string name,
        Func<CredentialFormFacts, bool, CredentialUsernameHint?, CredentialPendingCandidate?, double, CredentialCaptureDecision> decide) {
        Name = name;
        this.decide = decide;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialCaptureEvent? Named(string? name) => All.FirstOrDefault(captureEvent => captureEvent.Name == name);

    #endregion

    #region Actions - Capture

    /// What the observation `facts` of this event does to the page's credential
    /// state, given its remembered username `hint` and its `pending` candidate.
    public CredentialCaptureDecision Decide(CredentialFormFacts facts, CredentialUsernameHint? hint, CredentialPendingCandidate? pending,
        double now) {
        ArgumentNullException.ThrowIfNull(facts);
        bool accepted = facts.FrameOrigin.IsSecureUnder(facts.TopLevelOrigin);
        return decide(facts, accepted, hint, pending, now);
    }

    /// A focus offers the site's saved logins from a username or current
    /// password field, and a new password from a new password field. A
    /// username field offers logins only on a form that signs in, and only
    /// when some are saved; any other field closes the prompt.
    private static CredentialCaptureDecision Focused(CredentialFormFacts facts, bool accepted, CredentialUsernameHint? hint,
        CredentialPendingCandidate? pending, double now) {
        var form = SignInForm.Understand(facts.Fields);
        var role = facts.FocusedField is int focused ? form.RoleOf(focused) : null;
        if (role is null || role.NeedsLoginForm && !form.Purpose.OffersLogins)
            return CredentialCaptureDecision.For(CredentialCaptureAction.DismissFill);
        if (!accepted || !facts.HasFormId || !facts.HasFillTarget) return CredentialCaptureDecision.For(CredentialCaptureAction.Ignore);
        var source = UsernameSource(form, facts, hint, now);
        return CredentialCaptureDecision.For(CredentialCaptureAction.OfferFill, source, source == CredentialUsernameSource.None,
            facts.FrameOrigin != facts.TopLevelOrigin, facts.IsMainFrame, form, role.OfferedKind, role.NeedsLoginForm);
    }

    /// A form sent by its submit, Return or a control that sends it. A step
    /// naming the account is remembered for the next; otherwise the password
    /// it keeps becomes a candidate to save only when the person entered it,
    /// so a value the page or an extension put there never asks to be saved.
    private static CredentialCaptureDecision Sent(CredentialFormFacts facts, bool accepted, CredentialUsernameHint? hint,
        CredentialPendingCandidate? pending, double now) {
        if (!accepted || facts.Submission is not { SendsForm: true }) return CredentialCaptureDecision.For(CredentialCaptureAction.Ignore);
        var form = SignInForm.Understand(facts.Fields);
        if (form.Purpose.RemembersUsername)
            return CredentialCaptureDecision.For(SignInForm.FieldAt(facts.Fields, form.Username)?.HasValue == true
                ? CredentialCaptureAction.RememberUsername : CredentialCaptureAction.Ignore, form: form);
        if (SignInForm.FieldAt(facts.Fields, form.KeptPassword) is not { HasValue: true, EnteredByPerson: true })
            return CredentialCaptureDecision.For(CredentialCaptureAction.Ignore);
        var source = UsernameSource(form, facts, hint, now);
        if (source == CredentialUsernameSource.None && form.Purpose.FindsAccountByCurrentPassword
            && SignInForm.FieldAt(facts.Fields, form.CurrentPassword)?.HasValue == true)
            source = CredentialUsernameSource.CurrentPassword;
        if (source == CredentialUsernameSource.None)
            return CredentialCaptureDecision.For(CredentialCaptureAction.Ignore, clearsUsernameHint: true);
        return CredentialCaptureDecision.For(CredentialCaptureAction.CaptureCandidate, source,
            isCrossOriginFrame: facts.FrameOrigin != facts.TopLevelOrigin, form: form,
            passwordKind: form.KeptPassword == form.CurrentPassword ? CredentialPasswordKind.Current : CredentialPasswordKind.New);
    }

    /// The form's own username wins; otherwise a remembered one that still applies.
    private static CredentialUsernameSource UsernameSource(SignInForm form, CredentialFormFacts facts, CredentialUsernameHint? hint,
        double now) {
        if (SignInForm.FieldAt(facts.Fields, form.Username)?.HasValue == true) return CredentialUsernameSource.Explicit;
        return hint is not null && hint.Applies(facts.FrameOrigin, facts.TopLevelOrigin, now)
            ? CredentialUsernameSource.Hint : CredentialUsernameSource.None;
    }

    #endregion
}
