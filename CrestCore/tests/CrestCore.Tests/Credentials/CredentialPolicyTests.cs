using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class CredentialPolicyTests {
    private static readonly CredentialOrigin Login = new("https", "accounts.example.com", 443);
    private static readonly CredentialOrigin Embedded = new("https", "embedded.example.com", 443);
    private static readonly CredentialOrigin Plain = new("http", "accounts.example.com", 80);

    private static readonly CredentialOrigin Local = new("http", "localhost", 8080);

    private static FormField Field(int index, FormInputType type, string autocomplete = "", string name = "", bool visible = true,
        bool value = false, bool entered = false) =>
        new(index, type, autocomplete, name, "", "", "", visible, value, entered, null, null, null, "", []);

    private static readonly FormField Username = Field(0, FormInputType.Text, "username", value: true, entered: true);
    private static readonly FormField Password = Field(1, FormInputType.Password, "current-password", value: true, entered: true);

    private static CredentialFormFacts Facts(CredentialCaptureEvent kind, IReadOnlyList<FormField>? fields = null, int? focused = null,
        FormSubmission? sent = null, CredentialOrigin? frame = null, CredentialOrigin? top = null, bool? visible = null) =>
        new(kind, frame ?? Login, top ?? Login, true, true, fields ?? [Username, Password], focused, sent, false, visible, true, true);

    private static (int? Current, int? Kept) Read(IReadOnlyList<FormField> fields) {
        var form = SignInForm.Understand(fields);
        return (form.CurrentPassword, form.KeptPassword);
    }

    private static FormSubmission Sent(SubmitTrigger? trigger = null, bool inForm = true, string label = "") =>
        new(trigger ?? SubmitTrigger.FormSubmit, inForm, label);

    private static CredentialCaptureDecision Decide(CredentialFormFacts facts, CredentialUsernameHint? hint,
        CredentialPendingCandidate? pending, double now) =>
        facts.Event.Decide(facts, hint, pending, now);

    private static Rejection Refusal(Func<object?> rule) => Assert.Throws<Rejected>(rule).Rejection;

    [Fact]
    public void CaptureRequiresSecureFrameAndTopLevelOrigins() {
        Assert.True(Login.IsSecureUnder(Login));
        Assert.False(Plain.IsSecureUnder(Login));
        Assert.False(Login.IsSecureUnder(Plain));
        // A site served from this device is a secure context, as browsers treat it.
        Assert.True(Local.IsSecureUnder(Local));
        Assert.True(new CredentialOrigin("http", "127.0.0.1", 80).IsSecure);
        Assert.Equal(CredentialCaptureAction.Ignore,
            Decide(Facts(CredentialCaptureEvent.Submit, sent: Sent(), top: Plain), null, null, 0).Action);
        Assert.Equal(CredentialCaptureAction.Ignore,
            Decide(Facts(CredentialCaptureEvent.Submit, sent: Sent(), frame: Plain), null, null, 0).Action);
        Assert.Equal(CredentialCaptureAction.CaptureCandidate,
            Decide(Facts(CredentialCaptureEvent.Submit, sent: Sent(), frame: Local, top: Local), null, null, 0).Action);
        Assert.Equal(CredentialSaveValidity.InsecureOrigin, new CredentialPendingCandidate(Plain, 0).SaveValidity(Login, 1));
    }

    [Fact]
    public void OnlyAPasswordThePersonEnteredAndSentAsksToBeSaved() {
        var prefilled = Password with { EnteredByPerson = false };
        Assert.Equal(CredentialCaptureAction.Ignore,
            Decide(Facts(CredentialCaptureEvent.Submit, [Username, prefilled], sent: Sent()), null, null, 0).Action);
        // A button that doesn't say it sends the form, such as "Show password", sends nothing.
        Assert.Equal(CredentialCaptureAction.Ignore,
            Decide(Facts(CredentialCaptureEvent.Submit, sent: Sent(SubmitTrigger.Button, label: "Show")), null, null, 0).Action);
        Assert.Equal(CredentialCaptureAction.Ignore, Decide(Facts(CredentialCaptureEvent.Submit,
            sent: Sent(SubmitTrigger.SubmitControl, inForm: false, label: "")), null, null, 0).Action);
        Assert.Equal(CredentialCaptureAction.Ignore,
            Decide(Facts(CredentialCaptureEvent.Submit, sent: Sent(SubmitTrigger.Button, label: "Weiterlesen")), null, null, 0).Action);
        Assert.Equal(CredentialCaptureAction.Ignore,
            Decide(Facts(CredentialCaptureEvent.Submit, sent: Sent(SubmitTrigger.Button, label: "Continue as guest")), null, null, 0).Action);
        foreach (var sent in new[] {
            Sent(), Sent(SubmitTrigger.ReturnKey), Sent(SubmitTrigger.SubmitControl),
            Sent(SubmitTrigger.Button, inForm: false, label: "Sign in"), Sent(SubmitTrigger.Button, inForm: false, label: "Log-in"),
            Sent(SubmitTrigger.Button, label: "Weiter")
        }) {
            var decision = Decide(Facts(CredentialCaptureEvent.Submit, sent: sent), null, null, 0);
            Assert.Equal(CredentialCaptureAction.CaptureCandidate, decision.Action);
            Assert.Equal<(FormPurpose, int?, int?)>((FormPurpose.SignIn, 0, 1), (decision.Form.Purpose, decision.Form.Username, decision.Form.CurrentPassword));
        }
    }

    /// A field that takes a one-time code offers the site's codes, with the
    /// fields the code goes into, before anything a sign-in reading offers.
    [Fact]
    public void CodeFieldsOfferCodes() {
        FormField[] split = [.. Enumerable.Range(0, 6).Select(index =>
            new FormField(index, FormInputType.Text, "", $"digit{index}", "", "", "", true, false, false, null, 1, null, "numeric", []))];
        var offer = Decide(Facts(CredentialCaptureEvent.Focus, split, focused: 2), null, null, 0);
        Assert.Equal(CredentialCaptureAction.OfferFill, offer.Action);
        Assert.Null(offer.PasswordKind);
        Assert.Equal([0, 1, 2, 3, 4, 5], offer.CodeFields?.Fields);
        var code = Field(0, FormInputType.Text, "one-time-code");
        Assert.Equal([0], Decide(Facts(CredentialCaptureEvent.Focus, [code], focused: 0), null, null, 0).CodeFields?.Fields);
        Assert.Null(Decide(Facts(CredentialCaptureEvent.Focus, focused: 1), null, null, 0).CodeFields);
    }

    /// A field of a card or address section that signs nothing in offers
    /// the person's cards or addresses, for that section alone.
    [Fact]
    public void CheckoutFieldsOfferTheirSection() {
        FormField[] checkout = [Field(0, FormInputType.Text, "cc-name"), Field(1, FormInputType.Text, "cc-number"),
            Field(2, FormInputType.Text, "cc-exp")];
        var offer = Decide(Facts(CredentialCaptureEvent.Focus, checkout, focused: 1), null, null, 0);
        Assert.Equal<(CredentialCaptureAction, AutofillSectionKind?, int?)>(
            (CredentialCaptureAction.OfferFill, AutofillSectionKind.Card, 3), (offer.Action, offer.Autofill?.Kind, offer.Autofill?.Fields.Count));
        Assert.Null(offer.PasswordKind);
        Assert.Null(Decide(Facts(CredentialCaptureEvent.Focus, focused: 0), null, null, 0).Autofill);
    }

    [Fact]
    public void UsernameFieldsOfferWhatTheirFormsPasswordFieldsOffer() {
        var step = Field(0, FormInputType.Email, "username webauthn");
        var offer = Decide(Facts(CredentialCaptureEvent.Focus, [step], focused: 0), null, null, 0);
        Assert.Equal<(CredentialCaptureAction, CredentialPasswordKind?, bool)>((CredentialCaptureAction.OfferFill, CredentialPasswordKind.Current, true),
            (offer.Action, offer.PasswordKind, offer.QuietWithoutLogins));
        Assert.Equal(FormPurpose.UsernameStep, offer.Form.Purpose);
        // A sign-in form's username and password fields offer its logins,
        // and say so even before any are saved.
        foreach (int focused in new[] { 0, 1 }) {
            var signIn = Decide(Facts(CredentialCaptureEvent.Focus, focused: focused), null, null, 0);
            Assert.Equal<(CredentialCaptureAction, CredentialPasswordKind?, bool, int?)>(
                (CredentialCaptureAction.OfferFill, CredentialPasswordKind.Current, false, 1),
                (signIn.Action, signIn.PasswordKind, signIn.QuietWithoutLogins, signIn.Form.CurrentPassword));
        }
        // A newsletter's email field offers nothing; a sign-up form's email
        // field offers the new password its password fields do.
        var newsletter = Field(0, FormInputType.Email, "email", "email");
        Assert.Equal(CredentialCaptureAction.DismissFill,
            Decide(Facts(CredentialCaptureEvent.Focus, [newsletter], focused: 0), null, null, 0).Action);
        FormField[] signUp = [newsletter, Field(1, FormInputType.Password, "new-password"), Field(2, FormInputType.Password, "new-password")];
        foreach (int focused in new[] { 0, 1 }) {
            var fromField = Decide(Facts(CredentialCaptureEvent.Focus, signUp, focused: focused), null, null, 0);
            Assert.Equal<(CredentialCaptureAction, CredentialPasswordKind?, bool)>(
                (CredentialCaptureAction.OfferFill, CredentialPasswordKind.New, false),
                (fromField.Action, fromField.PasswordKind, fromField.QuietWithoutLogins));
        }
        var create = Decide(Facts(CredentialCaptureEvent.Focus, signUp, focused: 1), null, null, 0);
        Assert.Equal((FormPurpose.SignUp, (int?)0), (create.Form.Purpose, create.Form.Username));
        Assert.Equal([1, 2], create.Form.NewPasswords);
        // Sending the step remembers its username; a search or chat box is no step.
        Assert.Equal(CredentialCaptureAction.RememberUsername,
            Decide(Facts(CredentialCaptureEvent.Username, [step with { HasValue = true }], sent: Sent()), null, null, 0).Action);
        Assert.Equal(FormPurpose.None,
            Decide(Facts(CredentialCaptureEvent.Username, [Field(0, FormInputType.Text, name: "q", value: true)], sent: Sent()), null, null, 0)
                .Form.Purpose);
        Assert.Equal(FormPurpose.None,
            Decide(Facts(CredentialCaptureEvent.Username, [Field(0, FormInputType.Text, name: "message", value: true)], sent: Sent()), null,
                null, 0).Form.Purpose);
    }

    [Fact]
    public void AChangedPasswordKeepsTheNewOneForItsAccount() {
        var hidden = Field(0, FormInputType.Text, "username", visible: false, value: true);
        var current = Field(1, FormInputType.Password, "current-password", value: true, entered: true);
        var renewed = Field(2, FormInputType.Password, "new-password", value: true, entered: true);
        var confirmed = renewed with { Index = 3 };
        var change = Decide(Facts(CredentialCaptureEvent.Submit, [hidden, current, renewed, confirmed], sent: Sent()), null, null, 0);
        Assert.Equal((CredentialCaptureAction.CaptureCandidate, CredentialUsernameSource.Explicit), (change.Action, change.UsernameSource));
        Assert.Equal<(FormPurpose, int?, int?, int?)>((FormPurpose.ChangePassword, 0, 1, 2), (change.Form.Purpose, change.Form.Username, change.Form.CurrentPassword,
            change.Form.KeptPassword));
        // A field the page declares current wins over one whose label only mentions the current password.
        var mentioned = renewed with { Index = 0, Autocomplete = "", Label = "New password, not your current one" };
        var declared = current with { Index = 1 };
        Assert.Equal<(int?, int?)>((1, 0), Read([mentioned, declared]));
        // Three fields all declared new hold no current password.
        var newOnly = renewed with { Index = 0 };
        Assert.Null(SignInForm.Understand([newOnly, renewed with { Index = 1 }, renewed with { Index = 2 }]).CurrentPassword);
        // A field declared a username is one, even when its label says code.
        Assert.Equal(0, SignInForm.Understand([Field(0, FormInputType.Text, "username") with { Label = "Account code" }, Password])
            .Username);
        // A username field the page asks browsers not to fill is still the username.
        Assert.Equal(0, SignInForm.Understand([Field(0, FormInputType.Text, "off", "username"), Password]).Username);
        // Without a username, the saved login whose password is the current one names the account.
        var anonymous = Decide(Facts(CredentialCaptureEvent.Submit, [current, renewed, confirmed], sent: Sent()), null, null, 0);
        Assert.Equal(CredentialUsernameSource.CurrentPassword, anonymous.UsernameSource);
    }

    [Fact]
    public void AUsernameHintAppliesOnlyToItsExactOriginsWithinItsLifetime() {
        var hint = new CredentialUsernameHint(Login, Login, 1_000);
        Assert.True(hint.Applies(Login, Login, 1_001));
        Assert.True(hint.Applies(Login, Login, 1_000 + CredentialUsernameHint.Lifetime));
        Assert.False(hint.Applies(Embedded, Login, 1_001));
        Assert.False(hint.Applies(Login, Embedded, 1_001));
        Assert.False(hint.Applies(Login, Login, 1_001 + CredentialUsernameHint.Lifetime));
    }

    [Fact]
    public void TheSaveMatchIsTheMostRecentRecordForTheSameAccountIgnoringCase() {
        var older = new CredentialRecord(Guid.NewGuid(), "Person@Example.com", 1_000, null);
        var newer = new CredentialRecord(Guid.NewGuid(), "person@example.com", 2_000, null);
        var other = new CredentialRecord(Guid.NewGuid(), "someone", 3_000, null);
        Assert.Equal(newer, CredentialRecord.Matching("PERSON@example.com", [older, newer, other]));
        Assert.Null(CredentialRecord.Matching("nobody", [older, newer, other]));
        // Canonically equivalent spellings of one account match.
        var composed = new CredentialRecord(Guid.NewGuid(), "José", 1, null);
        Assert.Equal(composed, CredentialRecord.Matching("josé", [composed]));
        Assert.Null(CredentialRecord.Matching("person", [new(Guid.NewGuid(), "", 9, null)]));
        Assert.Equal(new InvalidCredentialRecord(), Refusal(() => CredentialRecord.Matching("person", [new(Guid.NewGuid(), null, 1, null)])));
        Assert.Equal(new InvalidCredentialUsername(), Refusal(() => CredentialRecord.Matching("", [composed])));
    }

    [Fact]
    public void AnUnchangedPasswordIsAlreadyStoredAndAMissingSecretCreatesARecord() {
        var id = Guid.NewGuid();
        Assert.Equal(new CredentialSavePlan(CredentialSavePlanKind.Create, null), CredentialSavePlan.For(null, null));
        Assert.Equal(new CredentialSavePlan(CredentialSavePlanKind.Create, null), CredentialSavePlan.For(id, null));
        var unchanged = CredentialSavePlan.For(id, new(id, PasswordMatches: true));
        Assert.Equal(new CredentialSavePlan(CredentialSavePlanKind.AlreadyStored, id), unchanged);
        Assert.False(unchanged.RequiresConfirmation);
        var changed = CredentialSavePlan.For(id, new(id, PasswordMatches: false));
        Assert.Equal(new CredentialSavePlan(CredentialSavePlanKind.Update, id), changed);
        Assert.True(changed.RequiresConfirmation);
        Assert.Equal(new StaleCredentialComparison(), Refusal(() => CredentialSavePlan.For(id, new(Guid.NewGuid(), true))));
        Assert.Equal(new StaleCredentialComparison(), Refusal(() => CredentialSavePlan.For(null, new(id, true))));
    }

    [Fact]
    public void GeneratedPasswordsFollowTheSitesRules() {
        var grouped = PasswordRequirements.None.Recipe(PasswordStyle.Grouped);
        Assert.Equal((3, 6, "-", 20), (grouped.Segments, grouped.SegmentLength, grouped.Separator, grouped.Length));
        Assert.All(grouped.Groups.Concat(grouped.Required), group => Assert.True(group.Length > 0 && group.IndexOfAny(['l', 'I', 'O', '0', '1']) < 0));
        // Rules the grouped style can't meet get random characters from what the site allows.
        var digits = new PasswordRequirements(null, null, "required: digit; maxlength: 8; max-consecutive: 2").Recipe(PasswordStyle.Grouped);
        Assert.Equal((1, 8, "", 2), (digits.Segments, digits.Length, digits.Separator, digits.MaxConsecutive));
        Assert.Equal(["23456789"], digits.Groups);
        var symbols = new PasswordRequirements(12, 16, "required: lower; required: upper; required: digit; required: [!#];").Recipe(PasswordStyle.Grouped);
        Assert.Equal(16, symbols.Length);
        Assert.Contains("!#", symbols.Required);
        Assert.DoesNotContain(symbols.Groups, group => group.Contains('-'));
        var allowed = new PasswordRequirements(8, 64, "required: upper; required: digit; allowed: lower, [-]; nonsense").Recipe(PasswordStyle.Grouped);
        Assert.Equal((grouped.Segments, grouped.Separator, grouped.Length), (allowed.Segments, allowed.Separator, allowed.Length));
        Assert.Equal(new InvalidPasswordLength(StrongPasswordRecipe.ShortestLength, StrongPasswordRecipe.MaximumLength),
            Refusal(() => new PasswordRequirements(null, 3, null).Recipe(PasswordStyle.Grouped)));
        // A random password with symbols is offered beside a grouped one, with what the site asked for.
        Assert.True(grouped.HasRandomAlternative);
        var random = PasswordRequirements.None.Recipe(PasswordStyle.Random);
        Assert.Equal(("", 20, 4), (random.Separator, random.SegmentLength, random.Required.Count));
        var signup = new PasswordRequirements(null, null,
            "minlength: 12; maxlength: 16; required: lower; required: upper; required: digit; required: [-_!]; allowed: [-_!]")
            .Recipe(PasswordStyle.Grouped);
        Assert.Equal<(int?, int?, string?)>((12, 16, "!-_"), (signup.SiteMinLength, signup.SiteMaxLength, signup.SiteSymbols));
        Assert.Null(PasswordRequirements.None.Recipe(PasswordStyle.Grouped).SiteSymbols);
        // A minimum past what Crest makes is refused, never lowered.
        Assert.IsType<InvalidPasswordLength>(Refusal(() => new PasswordRequirements(129, 200, null).Recipe(PasswordStyle.Grouped)));
        // Every required set is kept: one met by another's characters folds into it.
        var tight = new PasswordRequirements(null, null, "required: [ab]; required: [a]; required: [b]; required: [c]; required: [d]; maxlength: 4")
            .Recipe(PasswordStyle.Grouped);
        Assert.Equal(["a", "b", "c", "d"], tight.Required);
        // A repeat limit keeps the characters it needs, and a rule given twice holds to the stricter value.
        var alternating = new PasswordRequirements(null, null, "allowed: [al]; minlength: 4; maxlength: 4; max-consecutive: 2; max-consecutive: 1")
            .Recipe(PasswordStyle.Grouped);
        Assert.Equal(1, alternating.MaxConsecutive);
        Assert.Equal(["al"], alternating.Groups);
        // An empty set is ignored, and the rules after it still hold.
        var afterEmpty = new PasswordRequirements(null, null, "allowed: []; required: digit; maxlength: 8").Recipe(PasswordStyle.Grouped);
        Assert.Equal(8, afterEmpty.Length);
        Assert.Equal(["23456789"], afterEmpty.Groups);
        Assert.Contains("]", new PasswordRequirements(null, 16, "required: []]; required: lower").Recipe(PasswordStyle.Grouped).Required);
        // Characters outside the named classes, and semicolons inside a set, are the page's own.
        Assert.Contains("/", new PasswordRequirements(null, null, "required: lower; required: [/]").Recipe(PasswordStyle.Grouped).Required);
        Assert.Contains(new PasswordRequirements(null, 16, "required: [!;@]; required: lower").Recipe(PasswordStyle.Grouped).Required,
            group => group.Contains(';'));
    }

    [Fact]
    public void PasskeyAccessChecksTheCapabilityThenTheDeviceThenConsent() {
        Assert.Equal(PasskeyAccessStatus.ManagedCapabilityRequired,
            new PasskeyAccess(false, PasskeyDeviceConfiguration.NotConfigured, PasskeyAuthorizationState.Authorized).Status);
        Assert.Equal(PasskeyAccessStatus.DeviceNotConfigured,
            new PasskeyAccess(true, PasskeyDeviceConfiguration.NotConfigured, PasskeyAuthorizationState.Authorized).Status);
        Assert.Equal(PasskeyAccessStatus.Authorized,
            new PasskeyAccess(true, PasskeyDeviceConfiguration.Unknown, PasskeyAuthorizationState.Authorized).Status);
        Assert.Equal(PasskeyAccessStatus.Denied,
            new PasskeyAccess(true, PasskeyDeviceConfiguration.Configured, PasskeyAuthorizationState.Denied).Status);
        Assert.Equal(PasskeyAccessStatus.NotDetermined,
            new PasskeyAccess(true, PasskeyDeviceConfiguration.Configured, PasskeyAuthorizationState.NotDetermined).Status);
    }

    [Fact]
    public void SystemPasswordWriteThroughIsOfferedOnlyForAnOptedInOrdinarySpace() {
        Assert.True(new SystemPasswordOffer(true, SystemPasswordWriteThroughAvailability.Available, false).Offers);
        Assert.False(new SystemPasswordOffer(false, SystemPasswordWriteThroughAvailability.Available, false).Offers);
        Assert.False(new SystemPasswordOffer(true, SystemPasswordWriteThroughAvailability.Available, true).Offers);
        Assert.False(new SystemPasswordOffer(true, SystemPasswordWriteThroughAvailability.IsolatedLaunch, false).Offers);
    }
}
