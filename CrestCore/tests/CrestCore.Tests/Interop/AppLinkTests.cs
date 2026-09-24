using CrestCore.Contracts;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

/// External-link routing through the native app boundary: encoded queries in,
/// encoded answers out.
public sealed class AppLinkTests {
    private static readonly Guid Work = Guid.NewGuid(), Personal = Guid.NewGuid();

    [Fact]
    public void RoutingAndTheQuickWindowSiteAnswerThroughTheBoundary() {
        using var app = new AppClient();
        var preferences = new LinkRoutingPreferences([new(Guid.NewGuid(), true, LinkRouteMatch.Contains, "example.com", Personal)],
            ExternalLinkDestination.QuickWindow, null, true, null);
        ExternalLinkRoute Route(params Guid[] locked) =>
            new("https://example.com/", preferences, new([Work, Personal], Work, []), locked);

        Assert.Equal(new ExternalLinkPlacement(Personal, false, false), app.Ask(Route(), ContractCodec.ReadExternalLinkPlacement));
        Assert.Equal(new ExternalLinkPlacement(Work, true, true), app.Ask(Route(Personal), ContractCodec.ReadExternalLinkPlacement));
        Assert.Equal(new ExternalLinkPlacement(null, false, false),
            app.Ask(Route(Personal, Work), ContractCodec.ReadExternalLinkPlacement));
        Assert.Equal("example.com",
            app.Ask(new QuickWindowSite("https://www.Example.com/a", true), ContractCodec.ReadQuickWindowSiteKey).Site);
        Assert.Null(app.Ask(new QuickWindowSite("https://example.com/", false), ContractCodec.ReadQuickWindowSiteKey).Site);
    }
}
