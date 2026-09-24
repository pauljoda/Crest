using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void ABorrowedWorkspaceLeavesSpaceSettingsToItsSourceWhichNormalizesBranding() {
        var session = SavedSession().Document["session"]!;
        var owner = new NativeSessionAuthority(Bytes(session));
        var child = Borrow(owner, session);
        using var device = new TestDevice(owner);
        var borrowed = device.Attach(child);
        var space = SpaceId(session["spaces"]![0]!);
        var branding = StoredSessionCodec.DecodeBranding(new JsonObject { ["colors"] = new JsonArray(), ["bannerStrength"] = 2.0 });

        Assert.Equal(new BorrowedProfileRequiresOwner(borrowed),
            Assert.Throws<Rejected>(() => device.Send(new SetSpaceBranding(borrowed, space, branding))).Rejection);
        Assert.Equal(new BorrowedProfileRequiresOwner(borrowed),
            Assert.Throws<Rejected>(() => device.Send(new ReorderSpaces(borrowed, [space]))).Rejection);

        device.Send(new SetSpaceBranding(device.Workspace, space, branding));
        var stored = owner.Current.Spaces[0].Settings.Branding!;
        Assert.Single(stored.Colors.Colors);
        Assert.Equal(1.0, stored.BannerStrength);
        // The borrower reads the canonical branding through its source.
        child.PrepareBorrowedRefresh().Commit();
        Assert.Equal(stored, child.Current.Spaces[0].Settings.Branding);
    }
}
