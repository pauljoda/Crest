using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed class ApplePasswordsAvailabilityTests : IDisposable {
    private readonly CrestApp app = new(new AppConfiguration(null, DevicePlatform.Desktop));

    public void Dispose() => app.Dispose();

    private static readonly bool[] Both = [false, true];

    private static ApplePasswordsAvailability Passing(ApplePasswordsHelperFact? helper = null) =>
        new(IsMacPlatform: true, HasManagedBrowserCapability: true, IsLaunchIsolated: false, IsPrivateBrowsing: false,
            SpaceCredentialsEnabled: true, SpaceUsesApplePasswords: true, ApplePasswordsExtensionEnabled: false,
            Helper: helper ?? ApplePasswordsHelperFact.Paired);

    private ApplePasswordsSupport Ask(ApplePasswordsAvailability query) {
        return app.Query(query);
    }

    private static IEnumerable<ApplePasswordsAvailability> Everything() {
        var flags = Enumerable.Range(0, 1 << 7).ToArray();
        foreach (var bits in flags) {
            foreach (var helper in ApplePasswordsHelperFact.All) {
                bool Bit(int index) => (bits & (1 << index)) != 0;
                yield return new(Bit(0), Bit(1), Bit(2), Bit(3), Bit(4), Bit(5), Bit(6), helper);
            }
        }
    }

    /// Isolation and private browsing are the security property: whatever else
    /// is true, including a paired helper, neither may start the helper.
    [Fact]
    public void AnIsolatedLaunchOrAPrivateWindowNeverStartsTheHelper() {
        foreach (var query in Everything().Where(query => query.IsLaunchIsolated || query.IsPrivateBrowsing)) {
            var support = Ask(query);
            Assert.False(support.Status.StartsHelper, $"{query}");
            Assert.False(support.Status.OffersApplePasswords, $"{query}");
            Assert.False(support.OffersToTurnOffExtension, $"{query}");
        }
    }

    [Fact]
    public void EachFactFailingAloneYieldsItsStatus() {
        Assert.Same(ApplePasswordsStatus.UnsupportedPlatform, Ask(Passing() with { IsMacPlatform = false }).Status);
        Assert.Same(ApplePasswordsStatus.IsolatedLaunch, Ask(Passing() with { IsLaunchIsolated = true }).Status);
        Assert.Same(ApplePasswordsStatus.PrivateWindow, Ask(Passing() with { IsPrivateBrowsing = true }).Status);
        Assert.Same(ApplePasswordsStatus.ManagedBrowserCapabilityRequired, Ask(Passing() with { HasManagedBrowserCapability = false }).Status);
        Assert.Same(ApplePasswordsStatus.CredentialsDisabled, Ask(Passing() with { SpaceCredentialsEnabled = false }).Status);
        Assert.Same(ApplePasswordsStatus.TurnedOff, Ask(Passing() with { SpaceUsesApplePasswords = false }).Status);
        Assert.Same(ApplePasswordsStatus.HelperUnavailable, Ask(Passing(ApplePasswordsHelperFact.Unavailable)).Status);
        Assert.Same(ApplePasswordsStatus.HelperUnrecognized, Ask(Passing(ApplePasswordsHelperFact.Unrecognized)).Status);
        Assert.Same(ApplePasswordsStatus.PairingRequired, Ask(Passing(ApplePasswordsHelperFact.NotStarted)).Status);
        Assert.Same(ApplePasswordsStatus.PairingRequired, Ask(Passing(ApplePasswordsHelperFact.Unpaired)).Status);
        Assert.Same(ApplePasswordsStatus.Available, Ask(Passing()).Status);
    }

    [Fact]
    public void TheFirstFailingFactWins() {
        var allFailing = new ApplePasswordsAvailability(false, false, true, true, false, false, false, ApplePasswordsHelperFact.Unavailable);
        Assert.Same(ApplePasswordsStatus.UnsupportedPlatform, Ask(allFailing).Status);
        allFailing = allFailing with { IsMacPlatform = true };
        Assert.Same(ApplePasswordsStatus.IsolatedLaunch, Ask(allFailing).Status);
        allFailing = allFailing with { IsLaunchIsolated = false };
        Assert.Same(ApplePasswordsStatus.PrivateWindow, Ask(allFailing).Status);
        allFailing = allFailing with { IsPrivateBrowsing = false };
        Assert.Same(ApplePasswordsStatus.ManagedBrowserCapabilityRequired, Ask(allFailing).Status);
        allFailing = allFailing with { HasManagedBrowserCapability = true };
        Assert.Same(ApplePasswordsStatus.CredentialsDisabled, Ask(allFailing).Status);
        allFailing = allFailing with { SpaceCredentialsEnabled = true };
        Assert.Same(ApplePasswordsStatus.TurnedOff, Ask(allFailing).Status);
    }

    /// A helper that is missing, killed or unrecognized fails closed.
    [Fact]
    public void AnUnavailableOrUnrecognizedHelperNeverOffersOrStarts() {
        foreach (var helper in new[] { ApplePasswordsHelperFact.Unavailable, ApplePasswordsHelperFact.Unrecognized }) {
            foreach (var extension in Both) {
                var support = Ask(Passing(helper) with { ApplePasswordsExtensionEnabled = extension });
                Assert.False(support.Status.OffersApplePasswords);
                Assert.False(support.Status.StartsHelper);
                Assert.False(support.OffersToTurnOffExtension);
            }
        }
    }

    [Fact]
    public void OfferingToTurnOffTheExtensionNeedsAvailabilityAndAnEnabledExtension() {
        foreach (var query in Everything()) {
            var support = Ask(query);
            Assert.Equal(support.Status.OffersApplePasswords && query.ApplePasswordsExtensionEnabled, support.OffersToTurnOffExtension);
        }
        Assert.True(Ask(Passing() with { ApplePasswordsExtensionEnabled = true }).OffersToTurnOffExtension);
        Assert.False(Ask(Passing(ApplePasswordsHelperFact.Unpaired) with { ApplePasswordsExtensionEnabled = true }).OffersToTurnOffExtension);
    }

    [Fact]
    public void AStoredSpaceWithoutTheChoiceDoesNotUseApplePasswordsAndTheChoiceRoundTrips() {
        var older = StoredSessionCodec.DecodeCredentialPreferences(new JsonObject { ["isEnabled"] = true });
        Assert.False(older.UsesApplePasswords);

        var chosen = StoredSessionCodec.DefaultCredentialPreferences with { UsesApplePasswords = true };
        Assert.True(StoredSessionCodec.DecodeCredentialPreferences(StoredSessionCodec.Encode(chosen)).UsesApplePasswords);
    }
}
