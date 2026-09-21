using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed class SpaceAccessAuthorityTests
{
    private static SpaceAccessAssignment Assignment() => new(Guid.NewGuid(), Guid.NewGuid());

    [Fact]
    public void GrantsRequireMatchingRequestAndExactProfileAndCannotReplay()
    {
        var access = new SpaceAccessAuthority();
        var target = Assignment();
        var replacement = target with { Profile = Guid.NewGuid() };
        var request = access.Begin(target, true);
        Assert.True(access.IsLocked(target, true));
        Assert.Null(access.Complete(request, replacement, true));
        Assert.Null(access.Complete(request + 1, target, true));
        Assert.True(access.Complete(request, target, true));
        Assert.False(access.IsLocked(target, true));
        Assert.True(access.IsLocked(replacement, true));
        Assert.Null(access.Complete(request, target, true));
        Assert.True(new SpaceAccessAuthority().IsLocked(target, true));
    }

    [Fact]
    public void RelockingInvalidatesOldCompletionEvenAfterAnotherAttemptStarts()
    {
        var access = new SpaceAccessAuthority();
        var target = Assignment();
        var old = access.Begin(target, true);
        access.Lock(target.Space);
        var current = access.Begin(target, true);
        Assert.NotEqual(old, current);
        Assert.Null(access.Complete(old, target, true));
        Assert.True(access.IsLocked(target, true));
        Assert.True(access.Complete(current, target, true));
        Assert.False(access.IsLocked(target, true));
    }

    [Fact]
    public void InactiveScenePreservesPromptButExplicitLockAllCancelsItAndRevokesGrants()
    {
        var access = new SpaceAccessAuthority();
        var first = Assignment();
        var second = Assignment();
        Assert.True(access.Complete(access.Begin(first, true), first, true));
        var request = access.Begin(second, true);
        Assert.False(access.LockAll(inactiveScene: true));
        Assert.False(access.IsLocked(first, true));
        Assert.True(access.LockAll(inactiveScene: false));
        Assert.Null(access.Complete(request, second, true));
        Assert.True(access.IsLocked(first, true));
        Assert.True(access.IsLocked(second, true));
    }

    [Fact]
    public void DenialConsumesRequestAndAllowsRetryWithoutGrantingOtherProfiles()
    {
        var access = new SpaceAccessAuthority();
        var target = Assignment();
        var request = access.Begin(target, true);
        Assert.Equal("authentication_busy", Assert.Throws<BrowserRuleException>(() => access.Begin(target, true)).Code);
        Assert.Equal("authentication_busy", Assert.Throws<BrowserRuleException>(() => access.Begin(Assignment(), true)).Code);
        Assert.False(access.Complete(request, target, false));
        Assert.True(access.IsLocked(target, true));
        Assert.Null(access.Complete(request, target, true));
        Assert.True(access.Complete(access.Begin(target, true), target, true));
        Assert.Equal(0UL, access.Begin(target, true));
        Assert.Equal(0UL, access.Begin(Assignment(), false));
    }

    [Fact]
    public void LockingOneSpaceRevokesAllItsProfilesWithoutCancelingAnotherPrompt()
    {
        var access = new SpaceAccessAuthority();
        var first = Assignment();
        var replacement = first with { Profile = Guid.NewGuid() };
        var other = Assignment();
        Assert.True(access.Complete(access.Begin(first, true), first, true));
        Assert.True(access.Complete(access.Begin(replacement, true), replacement, true));
        var request = access.Begin(other, true);
        access.Lock(first.Space);
        Assert.True(access.IsLocked(first, true));
        Assert.True(access.IsLocked(replacement, true));
        Assert.True(access.Complete(request, other, true));
    }
}
