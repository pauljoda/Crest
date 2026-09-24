using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class CredentialPolicyTests {
    private static readonly CredentialOrigin Login = new("https", "accounts.example.com", 443);
    private static readonly CredentialOrigin Embedded = new("https", "embedded.example.com", 443);
    private static readonly CredentialOrigin Plain = new("http", "accounts.example.com", 80);

    private static CredentialFormFacts Facts(CredentialCaptureEvent kind, CredentialOrigin? frame = null,
        CredentialOrigin? top = null, bool mainFrame = true, bool username = false, bool password = false,
        CredentialPasswordKind? passwordKind = CredentialPasswordKind.Current, bool? visible = null, bool target = true) =>
        new(kind, frame ?? Login, top ?? Login, mainFrame, true, username, password, passwordKind, visible, target);

    private static Rejection Refusal(Func<object?> rule) => Assert.Throws<Rejected>(rule).Rejection;

    [Fact]
    public void CaptureRequiresSecureFrameAndTopLevelOrigins() {
        Assert.True(CredentialCapturePolicy.Accepts(Login, Login));
        Assert.False(CredentialCapturePolicy.Accepts(Plain, Login));
        Assert.False(CredentialCapturePolicy.Accepts(Login, Plain));
        Assert.Equal(CredentialCaptureAction.Ignore,
            CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Username, top: Plain, username: true), null, null, 0).Action);
        Assert.Equal(CredentialCaptureAction.Ignore,
            CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Submit, frame: Plain, username: true, password: true), null, null, 0).Action);
        Assert.Equal(CredentialSaveValidity.InsecureOrigin, CredentialCapturePolicy.SaveValidity(Plain, Login, 0, 1));
    }

    [Fact]
    public void SavedCredentialsFillCurrentPasswordFieldsAndGeneratedPasswordsFillNewOnes() {
        Assert.True(CredentialCapturePolicy.Offers(CredentialFillSource.Saved, CredentialPasswordKind.Current));
        Assert.False(CredentialCapturePolicy.Offers(CredentialFillSource.Saved, CredentialPasswordKind.New));
        Assert.True(CredentialCapturePolicy.Offers(CredentialFillSource.Generated, CredentialPasswordKind.New));
        Assert.False(CredentialCapturePolicy.Offers(CredentialFillSource.Generated, CredentialPasswordKind.Current));
    }

    [Fact]
    public void AUsernameHintAppliesOnlyToItsExactOriginsWithinItsLifetime() {
        var hint = new CredentialUsernameHint(Login, Login, 1_000);
        Assert.True(CredentialCapturePolicy.HintApplies(hint, Login, Login, 1_001));
        Assert.True(CredentialCapturePolicy.HintApplies(hint, Login, Login, 1_000 + CredentialCapturePolicy.UsernameHintLifetime));
        Assert.False(CredentialCapturePolicy.HintApplies(hint, Embedded, Login, 1_001));
        Assert.False(CredentialCapturePolicy.HintApplies(hint, Login, Embedded, 1_001));
        Assert.False(CredentialCapturePolicy.HintApplies(hint, Login, Login, 1_001 + CredentialCapturePolicy.UsernameHintLifetime));
    }

    [Fact]
    public void ASubmitTakesAnExplicitUsernameThenAnApplicableHintAndOtherwiseClearsTheHint() {
        var hint = new CredentialUsernameHint(Login, Login, 1_000);
        var explicitName = CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Submit, username: true, password: true), hint, null, 1_001);
        Assert.Equal(CredentialCapturePolicy.Decision(CredentialCaptureAction.CaptureCandidate, CredentialUsernameSource.Explicit), explicitName);

        var fromHint = CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Submit, password: true), hint, null, 1_001);
        Assert.Equal(CredentialUsernameSource.Hint, fromHint.UsernameSource);

        var expired = CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Submit, password: true), hint, null, 2_000);
        Assert.Equal(CredentialCapturePolicy.Decision(CredentialCaptureAction.Ignore, clearsUsernameHint: true), expired);

        var framed = CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Submit, frame: Embedded, username: true, password: true), null, null, 0);
        Assert.True(framed.IsCrossOriginFrame);
        Assert.Equal(CredentialCaptureAction.Ignore,
            CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Submit, username: true), null, null, 0).Action);
    }

    [Fact]
    public void AFocusWithoutAPasswordFieldDismissesAndOnlyAMainFrameFieldAnchorsItsPrompt() {
        Assert.Equal(CredentialCaptureAction.DismissFill,
            CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Focus, passwordKind: null), null, null, 0).Action);
        Assert.Equal(CredentialCaptureAction.Ignore,
            CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Focus, target: false), null, null, 0).Action);

        var main = CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Focus, username: true), null, null, 0);
        Assert.Equal(CredentialCapturePolicy.Decision(CredentialCaptureAction.OfferFill, CredentialUsernameSource.Explicit,
            anchorsToField: true), main);
        var framed = CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.Focus, frame: Embedded, mainFrame: false), null, null, 0);
        Assert.Equal(CredentialCapturePolicy.Decision(CredentialCaptureAction.OfferFill, CredentialUsernameSource.None, true, true), framed);
    }

    [Fact]
    public void ASaveIsOfferedOnlyOnceThePasswordFieldDisappearsBeforeTheCandidateExpires() {
        var pending = new CredentialPendingCandidate(Login, 1_000);
        Assert.Equal(CredentialCaptureAction.KeepPending,
            CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.DocumentState, visible: true), null, pending, 1_001).Action);
        Assert.Equal(CredentialCaptureAction.OfferSave,
            CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.DocumentState, visible: false), null, pending, 1_001).Action);
        Assert.Equal(CredentialCaptureAction.DiscardPending,
            CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.DocumentState, visible: false), null, pending,
                1_001 + CredentialCapturePolicy.CandidateLifetime).Action);
        Assert.Equal(CredentialCaptureAction.Ignore,
            CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.DocumentState, frame: Embedded, mainFrame: false, visible: false),
                null, pending, 1_001).Action);
        Assert.Equal(CredentialCaptureAction.Ignore,
            CredentialCapturePolicy.Decide(Facts(CredentialCaptureEvent.DocumentState, visible: false), null, null, 1_001).Action);
    }

    [Fact]
    public void StaleAndFutureCandidatesCannotBeSaved() {
        Assert.Equal(CredentialSaveValidity.Accepted, CredentialCapturePolicy.SaveValidity(Login, Login, 1_000, 1_000));
        Assert.Equal(CredentialSaveValidity.Accepted,
            CredentialCapturePolicy.SaveValidity(Login, Login, 1_000, 1_000 + CredentialCapturePolicy.CandidateLifetime));
        Assert.Equal(CredentialSaveValidity.Stale,
            CredentialCapturePolicy.SaveValidity(Login, Login, 1_000, 1_001 + CredentialCapturePolicy.CandidateLifetime));
        Assert.Equal(CredentialSaveValidity.Stale, CredentialCapturePolicy.SaveValidity(Login, Login, 1_000, 999));
        Assert.Equal(new InvalidCredentialDate(), Refusal(() => CredentialCapturePolicy.SaveValidity(Login, Login, double.NaN, 1)));
        Assert.Equal(new InvalidCredentialOrigin(),
            Refusal(() => CredentialCapturePolicy.SaveValidity(new("ftp", "accounts.example.com", 21), Login, 1, 1)));
    }

    [Fact]
    public void RecencyPrefersTheLatestUseThenTheLatestUpdateThenTheIdentity() {
        var low = Guid.Parse("00000000-0000-0000-0000-00000000000a");
        var high = Guid.Parse("f0000000-0000-0000-0000-000000000000");
        var usedLongAgo = new CredentialRecord(Guid.NewGuid(), null, 5_000, 100);
        var updatedRecently = new CredentialRecord(Guid.NewGuid(), null, 4_000, null);
        Assert.Equal(updatedRecently, CredentialRecencyPolicy.MostRecent([usedLongAgo, updatedRecently]));
        Assert.Equal(high, CredentialRecencyPolicy.MostRecent([new(high, null, 1, null), new(low, null, 1, null)])!.Id);
        Assert.Null(CredentialRecencyPolicy.MostRecent([]));

        var id = Guid.NewGuid();
        Assert.Equal(new DuplicateCredential(),
            Refusal(() => CredentialRecencyPolicy.MostRecent([new(id, null, 1, null), new(id, null, 2, null)])));
        Assert.Equal(new CredentialRecordLimitReached(CredentialRecencyPolicy.MaximumRecords), Refusal(() => CredentialRecencyPolicy.MostRecent(
            Enumerable.Range(0, CredentialRecencyPolicy.MaximumRecords + 1).Select(_ => new CredentialRecord(Guid.NewGuid(), null, 1, null)).ToArray())));
    }

    [Fact]
    public void TheSaveMatchIsTheMostRecentRecordForTheSameAccountIgnoringCase() {
        var older = new CredentialRecord(Guid.NewGuid(), "Person@Example.com", 1_000, null);
        var newer = new CredentialRecord(Guid.NewGuid(), "person@example.com", 2_000, null);
        var other = new CredentialRecord(Guid.NewGuid(), "someone", 3_000, null);
        Assert.Equal(newer, CredentialSavePolicy.Match("PERSON@example.com", [older, newer, other]));
        Assert.Null(CredentialSavePolicy.Match("nobody", [older, newer, other]));
        // Canonically equivalent spellings of one account match.
        var composed = new CredentialRecord(Guid.NewGuid(), "José", 1, null);
        Assert.Equal(composed, CredentialSavePolicy.Match("josé", [composed]));
        Assert.Null(CredentialSavePolicy.Match("person", [new(Guid.NewGuid(), "", 9, null)]));
        Assert.Equal(new InvalidCredentialRecord(), Refusal(() => CredentialSavePolicy.Match("person", [new(Guid.NewGuid(), null, 1, null)])));
        Assert.Equal(new InvalidCredentialUsername(), Refusal(() => CredentialSavePolicy.Match("", [composed])));
    }

    [Fact]
    public void AnUnchangedPasswordIsAlreadyStoredAndAMissingSecretCreatesARecord() {
        var id = Guid.NewGuid();
        Assert.Equal(new CredentialSavePlan(CredentialSavePlanKind.Create, null), CredentialSavePolicy.Plan(null, null));
        Assert.Equal(new CredentialSavePlan(CredentialSavePlanKind.Create, null), CredentialSavePolicy.Plan(id, null));
        var unchanged = CredentialSavePolicy.Plan(id, new(id, PasswordMatches: true));
        Assert.Equal(new CredentialSavePlan(CredentialSavePlanKind.AlreadyStored, id), unchanged);
        Assert.False(unchanged.RequiresConfirmation);
        var changed = CredentialSavePolicy.Plan(id, new(id, PasswordMatches: false));
        Assert.Equal(new CredentialSavePlan(CredentialSavePlanKind.Update, id), changed);
        Assert.True(changed.RequiresConfirmation);
        Assert.Equal(new StaleCredentialComparison(), Refusal(() => CredentialSavePolicy.Plan(id, new(Guid.NewGuid(), true))));
        Assert.Equal(new StaleCredentialComparison(), Refusal(() => CredentialSavePolicy.Plan(null, new(id, true))));
    }

    [Fact]
    public void GeneratedPasswordsUseFourUnambiguousGroupsWithinTheSupportedLengths() {
        var recipe = StrongPasswordPolicy.Recipe(null);
        Assert.Equal(StrongPasswordPolicy.DefaultLength, recipe.Length);
        Assert.Equal(4, recipe.Groups.Count);
        Assert.All(recipe.Groups, group => Assert.True(group.All(char.IsAscii) && !group.Any(char.IsWhiteSpace)));
        Assert.DoesNotContain(recipe.Groups, group => group.IndexOfAny(['l', 'I', 'O', '0', '1']) >= 0);
        Assert.Equal(64, StrongPasswordPolicy.Recipe(64).Length);
        Assert.Equal(new InvalidPasswordLength(16, 64), Refusal(() => StrongPasswordPolicy.Recipe(15)));
        Assert.IsType<InvalidPasswordLength>(Refusal(() => StrongPasswordPolicy.Recipe(65)));
    }

    [Fact]
    public void PasskeyAccessChecksTheCapabilityThenTheDeviceThenConsent() {
        Assert.Equal(PasskeyAccessStatus.ManagedCapabilityRequired,
            PasskeyAccessPolicy.Status(false, PasskeyDeviceConfiguration.NotConfigured, PasskeyAuthorizationState.Authorized));
        Assert.Equal(PasskeyAccessStatus.DeviceNotConfigured,
            PasskeyAccessPolicy.Status(true, PasskeyDeviceConfiguration.NotConfigured, PasskeyAuthorizationState.Authorized));
        Assert.Equal(PasskeyAccessStatus.Authorized,
            PasskeyAccessPolicy.Status(true, PasskeyDeviceConfiguration.Unknown, PasskeyAuthorizationState.Authorized));
        Assert.Equal(PasskeyAccessStatus.Denied,
            PasskeyAccessPolicy.Status(true, PasskeyDeviceConfiguration.Configured, PasskeyAuthorizationState.Denied));
        Assert.Equal(PasskeyAccessStatus.NotDetermined,
            PasskeyAccessPolicy.Status(true, PasskeyDeviceConfiguration.Configured, PasskeyAuthorizationState.NotDetermined));
    }

    [Theory]
    [InlineData(false, true, true, false, SystemPasswordWriteThroughAvailability.UnsupportedPlatform)]
    [InlineData(true, false, true, false, SystemPasswordWriteThroughAvailability.SystemVersionRequired)]
    [InlineData(true, true, false, false, SystemPasswordWriteThroughAvailability.ManagedBrowserCapabilityRequired)]
    [InlineData(true, false, false, true, SystemPasswordWriteThroughAvailability.IsolatedLaunch)]
    [InlineData(true, true, true, false, SystemPasswordWriteThroughAvailability.Available)]
    public void SystemPasswordWriteThroughNeedsTheMobileAPIAndManagedCapabilityOutsideIsolatedLaunches(bool mobile,
        bool systemApi, bool capability, bool isolated, SystemPasswordWriteThroughAvailability expected) =>
        Assert.Equal(expected, PasskeyAccessPolicy.WriteThroughAvailability(mobile, systemApi, capability, isolated));

    [Fact]
    public void SystemPasswordWriteThroughIsOfferedOnlyForAnOptedInOrdinarySpace() {
        Assert.True(PasskeyAccessPolicy.OffersWriteThrough(true, SystemPasswordWriteThroughAvailability.Available, false));
        Assert.False(PasskeyAccessPolicy.OffersWriteThrough(false, SystemPasswordWriteThroughAvailability.Available, false));
        Assert.False(PasskeyAccessPolicy.OffersWriteThrough(true, SystemPasswordWriteThroughAvailability.Available, true));
        Assert.False(PasskeyAccessPolicy.OffersWriteThrough(true, SystemPasswordWriteThroughAvailability.IsolatedLaunch, false));
    }
}
