using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class SitePermissionLedgerTests {
    private static readonly SiteOrigin Meet = new("https", "meet.example", 443);

    private static void Set(SitePermissionLedger ledger, Guid space, SitePermission permission, SitePermissionDecision decision,
        string? detail = null, SiteOrigin? origin = null, bool locked = false) =>
        ledger.Set(space, origin ?? Meet, permission, detail, decision, Guid.NewGuid(), 10, locked);

    [Fact]
    public void OriginsNormalizeCaseAndDefaultWebPorts() {
        Assert.Equal(new SiteOrigin("http", "news.example", 80), new SiteOrigin("HTTP", "News.Example", 0));
        Assert.Equal(new SiteOrigin("https", "news.example", 443), new SiteOrigin("HTTPS", "News.Example", -1));
        Assert.Equal(0, new SiteOrigin("custom", "Handler.Example", 0).Port);
        Assert.Equal("https://meet.example", Meet.DisplayName);
        Assert.Equal("https://meet.example:8443", new SiteOrigin("https", "meet.example", 8443).DisplayName);
        Assert.Throws<BrowserRuleException>(() => new SiteOrigin("https", "", 443));
    }

    [Fact]
    public void DecisionsAreScopedToSpaceOriginAndCapability() {
        var ledger = new SitePermissionLedger();
        Guid work = Guid.NewGuid(), personal = Guid.NewGuid();
        Set(ledger, work, SitePermission.Camera, SitePermissionDecision.GrantForSession);

        Assert.Equal(SitePermissionDecision.GrantForSession, ledger.Decision(work, Meet, SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(work, Meet, SitePermission.Microphone, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(work, new("https", "meet.example", 8443), SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(personal, Meet, SitePermission.Camera, null, false));
    }

    [Fact]
    public void SessionChoicesOverrideWithoutReplacingOrPersisting() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        var outcome = ledger.Set(space, Meet, SitePermission.Camera, null, SitePermissionDecision.DenyForSession, Guid.NewGuid(), 20, false);

        Assert.False(outcome.PersistenceChanged);
        Assert.True(Assert.Single(outcome.Changes).RevokesAuthorization);
        Assert.Equal(SitePermissionDecision.DenyForSession, ledger.Decision(space, Meet, SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.GrantPersistently, Assert.Single(ledger.PersistentRecords).Decision);

        var restarted = new SitePermissionLedger();
        restarted.Restore(ledger.PersistentRecords);
        Assert.Equal(SitePermissionDecision.GrantPersistently, restarted.Decision(space, Meet, SitePermission.Camera, null, false));

        ledger.ResetSession();
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision(space, Meet, SitePermission.Camera, null, false));
    }

    [Fact]
    public void ChangingASavedChoiceKeepsItsIdentityAndAskRemovesIt() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.Microphone, SitePermissionDecision.GrantPersistently);
        var original = Assert.Single(ledger.PersistentRecords).Id;

        ledger.Set(space, Meet, SitePermission.Microphone, null, SitePermissionDecision.DenyPersistently, Guid.NewGuid(), 30, false);
        var record = Assert.Single(ledger.PersistentRecords);
        Assert.Equal(original, record.Id);
        Assert.Equal(30, record.ModifiedAt);

        var cleared = ledger.Set(space, Meet, SitePermission.Microphone, null, SitePermissionDecision.Ask, Guid.NewGuid(), 40, false);
        Assert.True(cleared.PersistenceChanged);
        Assert.Empty(ledger.PersistentRecords);
    }

    [Fact]
    public void ANarrowChoiceWinsAndTheSiteWideRuleCoversTheRest() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.DenyPersistently);
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, "mailto");
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, "tel");

        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision(space, Meet, SitePermission.ExternalApplications, "mailto", false));
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.Decision(space, Meet, SitePermission.ExternalApplications, "zoommtg", false));

        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.Ask, "mailto");
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.Decision(space, Meet, SitePermission.ExternalApplications, "mailto", false));
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision(space, Meet, SitePermission.ExternalApplications, "tel", false));
        Assert.Throws<BrowserRuleException>(() => ledger.Decision(space, Meet, SitePermission.ExternalApplications, "", false));
    }

    [Fact]
    public void CombinedMediaCannotBypassAnIndividualBlock() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.CameraAndMicrophone, SitePermissionDecision.GrantPersistently);
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.DenyPersistently);

        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.MediaDecision(space, Meet, MediaPermission.CameraAndMicrophone, false));
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.MediaDecision(space, Meet, MediaPermission.Camera, false));
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.MediaDecision(space, Meet, MediaPermission.Microphone, false));

        Set(ledger, space, SitePermission.CameraAndMicrophone, SitePermissionDecision.Ask);
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        Assert.Equal(SitePermissionDecision.Ask, ledger.MediaDecision(space, Meet, MediaPermission.CameraAndMicrophone, false));
        Set(ledger, space, SitePermission.Microphone, SitePermissionDecision.GrantForSession);
        Assert.Equal(SitePermissionDecision.GrantForSession, ledger.MediaDecision(space, Meet, MediaPermission.CameraAndMicrophone, false));
    }

    [Fact]
    public void ALockedSpaceNeverAnswersListsOrRecords() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        Set(ledger, space, SitePermission.Microphone, SitePermissionDecision.GrantForSession);

        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(space, Meet, SitePermission.Camera, null, true));
        Assert.Equal(SitePermissionDecision.Ask, ledger.MediaDecision(space, Meet, MediaPermission.Microphone, true));
        Assert.Empty(ledger.Records(space, true));
        var rejected = ledger.Set(space, Meet, SitePermission.Location, null, SitePermissionDecision.GrantPersistently, Guid.NewGuid(), 1, true);
        Assert.False(rejected.Applied);
        Assert.Empty(rejected.Changes);
        Assert.Single(ledger.PersistentRecords);

        // Removal still applies, so a locked Space can be reset or deleted.
        Assert.True(ledger.ResetSpace(space).PersistenceChanged);
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(space, Meet, SitePermission.Microphone, null, false));
    }

    [Fact]
    public void ResettingASpaceLeavesOtherSpacesAlone() {
        var ledger = new SitePermissionLedger();
        Guid work = Guid.NewGuid(), personal = Guid.NewGuid();
        Set(ledger, work, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        Set(ledger, personal, SitePermission.Camera, SitePermissionDecision.DenyPersistently);
        Set(ledger, work, SitePermission.Microphone, SitePermissionDecision.DenyForSession);

        var change = Assert.Single(ledger.ResetSpace(work).Changes);
        Assert.Equal(work, change.Space);
        Assert.Null(change.Origin);
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(work, Meet, SitePermission.Microphone, null, false));
        Assert.Equal(personal, Assert.Single(ledger.PersistentRecords).Space);

        var record = ledger.PersistentRecords[0];
        Assert.Equal(record.Permission, Assert.Single(ledger.ResetRecord(record.Id).Changes).Permission);
        Assert.False(ledger.ResetRecord(record.Id).Applied);
    }

    [Fact]
    public void RecordsListByOriginNaturallyThenCapabilityThenDetail() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.Popups, SitePermissionDecision.GrantPersistently, origin: new("https", "b.example", 443));
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently, origin: new("https", "host10.example", 443));
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently, origin: new("https", "host9.example", 443));
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, "tel", new("https", "b.example", 443));
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, "mailto", new("https", "b.example", 443));
        Set(ledger, space, SitePermission.AutomaticDownloads, SitePermissionDecision.DenyPersistently, origin: new("https", "b.example", 443));

        var listed = ledger.Records(space, false).Select(record => $"{record.Origin.Host}/{record.Permission}/{record.Detail}");
        Assert.Equal([
            "b.example/AutomaticDownloads/", "b.example/ExternalApplications/mailto", "b.example/ExternalApplications/tel",
            "b.example/Popups/", "host9.example/Camera/", "host10.example/Camera/"
        ], listed);
    }

    [Fact]
    public void RestoreKeepsOnlyTheFirstPersistentRecordForEachChoice() {
        var space = Guid.NewGuid();
        var first = new SitePermissionRecord(Guid.NewGuid(), space, Meet, SitePermission.Camera, null, SitePermissionDecision.GrantPersistently, 1);
        var ledger = new SitePermissionLedger();
        int kept = ledger.Restore([
            first,
            first with { Id = Guid.NewGuid(), Decision = SitePermissionDecision.DenyPersistently },
            first with { Id = Guid.NewGuid(), Permission = SitePermission.Microphone, Decision = SitePermissionDecision.GrantForSession },
            first with { Id = Guid.NewGuid(), Permission = SitePermission.Location, Detail = "" },
        ]);

        Assert.Equal(1, kept);
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision(space, Meet, SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(space, Meet, SitePermission.Microphone, null, false));
    }
}
