using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed class HttpAuthenticationPlanTests {
    [Fact]
    public void FirstAttemptOnSecureOriginUsesStoredCredential() {
        using var app = new CrestApp(new(StorageDirectory: null, Platform: DevicePlatform.Desktop));

        var decision = app.Query(new HttpAuthenticationChallengePlan(
            AllowsCredentialSaving: true,
            IsSecureOrigin: true,
            PreviousFailureCount: 0,
            HasStoredCredential: true,
            AttemptedSameProtectionSpace: false,
            ProposedUsername: null,
            AttemptedUsername: null));

        Assert.True(decision.UsesStoredCredential);
        Assert.False(decision.StoredCredentialRejected);
        Assert.True(decision.AllowsSaving);
    }

    [Fact]
    public void FailedAttemptMarksMatchingStoredCredentialRejectedAndSuggestsItsUsername() {
        using var app = new CrestApp(new(StorageDirectory: null, Platform: DevicePlatform.Desktop));

        var decision = app.Query(new HttpAuthenticationChallengePlan(
            AllowsCredentialSaving: true,
            IsSecureOrigin: true,
            PreviousFailureCount: 1,
            HasStoredCredential: false,
            AttemptedSameProtectionSpace: true,
            ProposedUsername: null,
            AttemptedUsername: "alice"));

        Assert.False(decision.UsesStoredCredential);
        Assert.True(decision.StoredCredentialRejected);
        Assert.Equal("alice", decision.SuggestedUsername);
        Assert.True(decision.AllowsSaving);
    }

    [Fact]
    public void InsecureOriginRefusesStoredFillAndSaving() {
        using var app = new CrestApp(new(StorageDirectory: null, Platform: DevicePlatform.Desktop));

        var challenge = app.Query(new HttpAuthenticationChallengePlan(
            AllowsCredentialSaving: true,
            IsSecureOrigin: false,
            PreviousFailureCount: 0,
            HasStoredCredential: true,
            AttemptedSameProtectionSpace: false,
            ProposedUsername: "bob",
            AttemptedUsername: null));
        var save = app.Query(new HttpAuthenticationSavePlan(
            AllowsCredentialSaving: true,
            IsSecureOrigin: false,
            UserRequestedSave: true,
            SubmittedUsername: "bob",
            RejectedUsername: "bob"));

        Assert.False(challenge.UsesStoredCredential);
        Assert.False(challenge.AllowsSaving);
        Assert.Equal("bob", challenge.SuggestedUsername);
        Assert.False(save.ShouldSave);
        Assert.False(save.ReplacesRejectedCredential);
    }

    [Fact]
    public void SavePlanReplacesRejectedCredentialOnlyForSameUsername() {
        using var app = new CrestApp(new(StorageDirectory: null, Platform: DevicePlatform.Desktop));

        var sameAccount = app.Query(new HttpAuthenticationSavePlan(
            AllowsCredentialSaving: true,
            IsSecureOrigin: true,
            UserRequestedSave: true,
            SubmittedUsername: "alice",
            RejectedUsername: "alice"));
        var differentAccount = app.Query(new HttpAuthenticationSavePlan(
            AllowsCredentialSaving: true,
            IsSecureOrigin: true,
            UserRequestedSave: true,
            SubmittedUsername: "charlie",
            RejectedUsername: "alice"));

        Assert.True(sameAccount.ShouldSave);
        Assert.True(sameAccount.ReplacesRejectedCredential);
        Assert.True(differentAccount.ShouldSave);
        Assert.False(differentAccount.ReplacesRejectedCredential);
    }
}
