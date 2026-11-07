using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The sites where a Space blocks nothing: the device store keeps a
/// persistent Space's sites, which hold for that Space alone, and a Space
/// whose policy is off blocks nowhere.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ASpaceTurnsBlockingOffForOneSiteAndTheDeviceKeepsIt() {
        using var directory = new StorageDirectory();
        var site = new SiteOrigin("https", "news.example", 443);
        var other = new SiteOrigin("https", "shop.example", 443);
        Guid space, otherSpace;
        {
            var (app, _, spaces) = DeviceApp(directory);
            using var disposal = app;
            space = SpaceId(spaces[0]!);
            otherSpace = SpaceId(spaces[1]!);
            Assert.True(app.Query(new ContentBlockingApplies(space, site)));

            var changed = Assert.Single(app.Send(new SetSiteContentBlocking(space, site, Blocks: false)).OfType<SiteContentBlockingChanged>());
            Assert.Equal([new SiteContentBlocking(space, site)], changed.Sites);
            Assert.False(app.Query(new ContentBlockingApplies(space, site)));
            Assert.True(app.Query(new ContentBlockingApplies(space, other)));
            Assert.True(app.Query(new ContentBlockingApplies(otherSpace, site)));
            Assert.Empty(app.Send(new SetSiteContentBlocking(space, site, Blocks: false)));
            Assert.IsType<InvalidSiteOrigin>(Refusal(app, new SetSiteContentBlocking(space, new SiteOrigin("https", "", 443), false)));
            app.Send(new SetFilterList(FilterList.EasyListCookie, IsOn: true));
        }
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            Assert.Equal([new SiteContentBlocking(space, site)], app.Query(new GetSiteContentBlocking()));
            Assert.False(app.Query(new ContentBlockingApplies(space, site)));
            Assert.True(app.Query(new GetFilterLists()).Single(state => state.List == FilterList.EasyListCookie).IsOn);

            app.Send(new SetSiteContentBlocking(space, site, Blocks: true));
            Assert.True(app.Query(new ContentBlockingApplies(space, site)));
            Assert.Empty(app.Query(new GetSiteContentBlocking()));
        }
    }
}
