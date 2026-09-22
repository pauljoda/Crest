using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void ABorrowedWorkspaceSendsProfileSettingsToItsSourceWhichNormalizesBranding() {
        var session = SavedSession().Document["session"]!;
        var owner = new NativeSessionAuthority(Bytes(session));
        var child = Borrow(owner, session);
        var borrowed = JsonNode.Parse(child.PrepareBorrowedRefresh(1).Output)!["session"]!;
        var branding = new JsonObject { ["colors"] = new JsonArray(), ["bannerStrength"] = 2.0, ["futureBanner"] = "kept" };

        Assert.Equal(BrowserRuleCodes.BorrowedProfileRequiresOwner, Assert.Throws<BrowserRuleException>(() =>
            child.PrepareCommand(1, SpaceCommand(borrowed, "space.branding", new() { ["value"] = branding.DeepClone() }))).Code);
        Assert.Equal(BrowserRuleCodes.BorrowedProfile, Assert.Throws<BrowserRuleException>(() =>
            child.PrepareCommand(1, SpaceCommand(borrowed, "space.reorder", new() {
                ["offsets"] = new JsonArray(0),
                ["destination"] = 1
            }))).Code);

        var applied = owner.PrepareCommand(owner.Revision, SpaceCommand(session, "space.branding", new() { ["value"] = branding }));
        applied.Commit();
        var stored = JsonNode.Parse(applied.Output)!["session"]!["spaces"]![0]!["branding"]!;
        Assert.Single(stored["colors"]!.AsArray());
        Assert.Equal(1.0, stored["bannerStrength"]!.GetValue<double>());
        Assert.Equal("kept", stored["futureBanner"]!.GetValue<string>());
        // The borrower reads the canonical branding through its source.
        var refreshed = JsonNode.Parse(child.PrepareBorrowedRefresh(child.Revision).Output)!["session"]!;
        Assert.True(JsonNode.DeepEquals(stored, refreshed["spaces"]![0]!["branding"]));
    }
}
