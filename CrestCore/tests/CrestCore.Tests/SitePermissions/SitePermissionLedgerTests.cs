using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class SitePermissionLedgerTests {
    private static readonly SiteOrigin Meet = new("https", "meet.example", 443);

    private static void Set(SitePermissionLedger ledger, Guid space, SitePermission permission, SitePermissionDecision decision,
        string? detail = null, SiteOrigin? origin = null) =>
        ledger.Set([space], origin ?? Meet, permission, detail, decision, Guid.NewGuid(), 10);

    [Fact]
    public void DecisionsAreScopedToSpaceOriginAndCapability() {
        var ledger = new SitePermissionLedger();
        Guid work = Guid.NewGuid(), personal = Guid.NewGuid();
        Set(ledger, work, SitePermission.Camera, SitePermissionDecision.GrantForSession);

        Assert.Equal(SitePermissionDecision.GrantForSession, ledger.Decision([work], Meet, SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision([work], Meet, SitePermission.Microphone, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision([work], new("https", "meet.example", 8443), SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision([personal], Meet, SitePermission.Camera, null, false));
    }

    [Fact]
    public void SessionChoicesOverrideWithoutReplacingOrPersisting() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        var outcome = ledger.Set([space], Meet, SitePermission.Camera, null, SitePermissionDecision.DenyForSession, Guid.NewGuid(), 20);

        Assert.False(outcome.PersistenceChanged);
        Assert.True(Assert.Single(outcome.Changes).Scope.RevokesAuthorization);
        Assert.Equal(SitePermissionDecision.DenyForSession, ledger.Decision([space], Meet, SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.GrantPersistently, Assert.Single(ledger.PersistentRecords).Decision);

        var restarted = new SitePermissionLedger();
        restarted.Restore(ledger.PersistentRecords);
        Assert.Equal(SitePermissionDecision.GrantPersistently, restarted.Decision([space], Meet, SitePermission.Camera, null, false));

        // Restoring the kept records leaves the session's own choices in place.
        ledger.Restore(ledger.PersistentRecords.ToArray());
        Assert.Equal(SitePermissionDecision.DenyForSession, ledger.Decision([space], Meet, SitePermission.Camera, null, false));
    }

    [Fact]
    public void ANarrowChoiceWinsAndTheSiteWideRuleCoversTheRest() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.DenyPersistently);
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, "mailto");
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, "tel");

        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision([space], Meet, SitePermission.ExternalApplications, "mailto", false));
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.Decision([space], Meet, SitePermission.ExternalApplications, "zoommtg", false));

        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.Ask, "mailto");
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.Decision([space], Meet, SitePermission.ExternalApplications, "mailto", false));
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision([space], Meet, SitePermission.ExternalApplications, "tel", false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision([space], Meet, SitePermission.ExternalApplications, "", false));
        Assert.Equal(new InvalidSitePermissionDetail(SitePermissionLedger.MaximumDetailLength), Assert.Throws<Rejected>(() =>
            Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, new string('x', 257))).Rejection);
    }

    [Fact]
    public void CombinedMediaCannotBypassAnIndividualBlock() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.CameraAndMicrophone, SitePermissionDecision.GrantPersistently);
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.DenyPersistently);

        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.MediaDecision([space], Meet, SitePermission.CameraAndMicrophone, false));
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.MediaDecision([space], Meet, SitePermission.Camera, false));
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.MediaDecision([space], Meet, SitePermission.Microphone, false));

        Set(ledger, space, SitePermission.CameraAndMicrophone, SitePermissionDecision.Ask);
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        Assert.Equal(SitePermissionDecision.Ask, ledger.MediaDecision([space], Meet, SitePermission.CameraAndMicrophone, false));
        Set(ledger, space, SitePermission.Microphone, SitePermissionDecision.GrantForSession);
        Assert.Equal(SitePermissionDecision.GrantForSession, ledger.MediaDecision([space], Meet, SitePermission.CameraAndMicrophone, false));
    }

    [Fact]
    public void ResettingASpaceLeavesOtherSpacesAlone() {
        var ledger = new SitePermissionLedger();
        Guid work = Guid.NewGuid(), personal = Guid.NewGuid();
        Set(ledger, work, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        Set(ledger, personal, SitePermission.Camera, SitePermissionDecision.DenyPersistently);
        Set(ledger, work, SitePermission.Microphone, SitePermissionDecision.DenyForSession);

        var change = Assert.Single(ledger.ResetSpace([work]).Changes);
        Assert.Equal(work, change.Space);
        Assert.Null(change.Scope.Origin);
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision([work], Meet, SitePermission.Microphone, null, false));
        Assert.Equal(personal, Assert.Single(ledger.PersistentRecords).Space);

        var record = ledger.PersistentRecords[0];
        Assert.Equal(record.Permission, Assert.Single(ledger.ResetRecord(record.Id, space => [space]).Changes).Scope.Permission);
        Assert.Same(SitePermissionOutcome.Unchanged, ledger.ResetRecord(record.Id, space => [space]));
    }

    /// The Spaces of a group share one session, so a choice made in any of
    /// them answers in all, a Space that joins yields to what the group chose,
    /// and a successor keeps what a deleted primary chose for the group.
    [Fact]
    public void AGroupSharesItsChoicesAndAJoiningSpaceYieldsToThem() {
        var ledger = new SitePermissionLedger();
        Guid primary = Guid.NewGuid(), member = Guid.NewGuid(), joining = Guid.NewGuid();
        IReadOnlyList<Guid> group = [primary, member];
        Set(ledger, joining, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        ledger.Set(group, Meet, SitePermission.Camera, null, SitePermissionDecision.DenyPersistently, Guid.NewGuid(), 20);
        ledger.Set([member, primary], Meet, SitePermission.Microphone, null, SitePermissionDecision.GrantPersistently, Guid.NewGuid(), 30);

        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.Decision([member, primary], Meet, SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision(group, Meet, SitePermission.Microphone, null, false));
        ledger.Joining(joining, group);
        IReadOnlyList<Guid> joined = [primary, member, joining];
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.Decision(joined, Meet, SitePermission.Camera, null, false));
        Assert.Equal(2, ledger.Records(joined).Count);

        ledger.Set(joined, Meet, SitePermission.Camera, null, SitePermissionDecision.Ask, Guid.NewGuid(), 40);
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(joined, Meet, SitePermission.Camera, null, false));
        ledger.HandingOver(primary, member);
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision([member, joining], Meet, SitePermission.Microphone, null, false));
        Assert.DoesNotContain(ledger.PersistentRecords, record => record.Space == primary);
    }

    /// A session answer is the group's until the process ends: it overrides
    /// every Space's saved choice without removing it, a joining Space's own
    /// session answer yields to what the group chose, and a successor keeps
    /// the session answers of the primary it replaces beside its own.
    [Fact]
    public void AGroupSessionAnswerKeepsSavedChoicesAndOutlivesItsPrimary() {
        var ledger = new SitePermissionLedger();
        Guid primary = Guid.NewGuid(), member = Guid.NewGuid(), joining = Guid.NewGuid();
        IReadOnlyList<Guid> group = [primary, member];
        Set(ledger, member, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        var answered = ledger.Set(group, Meet, SitePermission.Camera, null, SitePermissionDecision.DenyForSession, Guid.NewGuid(), 20);
        Assert.False(answered.PersistenceChanged);
        Assert.Equal(member, Assert.Single(ledger.PersistentRecords).Space);
        Assert.Equal(SitePermissionDecision.DenyForSession, ledger.Decision(group, Meet, SitePermission.Camera, null, false));

        ledger.Set(group, Meet, SitePermission.Microphone, null, SitePermissionDecision.DenyPersistently, Guid.NewGuid(), 30);
        Set(ledger, joining, SitePermission.Microphone, SitePermissionDecision.GrantForSession);
        Assert.NotSame(SitePermissionOutcome.Unchanged, ledger.Joining(joining, group));
        IReadOnlyList<Guid> joined = [primary, member, joining];
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.Decision(joined, Meet, SitePermission.Microphone, null, false));

        Set(ledger, member, SitePermission.Location, SitePermissionDecision.GrantForSession);
        Assert.NotSame(SitePermissionOutcome.Unchanged, ledger.HandingOver(primary, member));
        IReadOnlyList<Guid> handed = [member, joining];
        Assert.Equal(SitePermissionDecision.DenyForSession, ledger.Decision(handed, Meet, SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.GrantForSession, ledger.Decision(handed, Meet, SitePermission.Location, null, false));
    }

}
