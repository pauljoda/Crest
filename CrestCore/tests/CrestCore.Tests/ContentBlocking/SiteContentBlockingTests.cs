using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The sites where a Space blocks nothing: the device store keeps a
/// persistent Space's sites, which hold for that Space alone, and a Space
/// whose policy is off blocks nowhere. It keeps the lists the person added and
/// their own filters too, including the rules Block Element adds per site.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ASpaceTurnsBlockingOffForOneSiteAndTheDeviceKeepsIt() {
        using var directory = new StorageDirectory();
        var site = new SiteOrigin("https", "news.example", 443);
        var other = new SiteOrigin("https", "shop.example", 443);
        Guid space, otherSpace;
        var listId = Guid.NewGuid();
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
            var added = Assert.Single(app.Send(new AddCustomFilterList(listId, "https://lists.example/mine.txt")).OfType<FilterListsChanged>());
            Assert.Equal("https://lists.example/mine.txt", Assert.Single(added.Lists.CustomLists).List.Url);
            Assert.Empty(app.Send(new AddCustomFilterList(Guid.NewGuid(), "https://lists.example/mine.txt")));
            Assert.IsType<FilterListAddressInvalid>(Refusal(app, new AddCustomFilterList(Guid.NewGuid(), "file:///etc/hosts")));
            Assert.IsType<FilterListAddressInvalid>(Refusal(app, new AddCustomFilterList(Guid.NewGuid(), "http://lists.example/plain.txt")));
            app.Send(new SetCustomFilters("||own-ads.example^"));
            Assert.IsType<CustomFiltersTooLarge>(Refusal(app, new SetCustomFilters(new string('x', Device.MaximumCustomFiltersBytes + 1))));
        }
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            Assert.Equal([new SiteContentBlocking(space, site)], app.Query(new GetSiteContentBlocking()));
            Assert.False(app.Query(new ContentBlockingApplies(space, site)));
            var lists = app.Query(new GetFilterLists());
            Assert.True(lists.Lists.Single(state => state.List == FilterList.EasyListCookie).IsOn);
            Assert.Equal(new CustomFilterList(listId, "https://lists.example/mine.txt", IsOn: true), Assert.Single(lists.CustomLists).List);
            Assert.Equal("||own-ads.example^", lists.CustomFilters);
            // Block Element adds a site's rule once; showing the site's elements
            // again removes that site's rules alone.
            app.Send(new BlockElement("https://news.example/story", "div.promo"));
            Assert.Empty(app.Send(new BlockElement("https://news.example/other", " div.promo ")));
            app.Send(new BlockElement("https://shop.example/", ".banner"));
            Assert.IsType<ElementSelectorInvalid>(Refusal(app, new BlockElement("about:blank", "div")));
            Assert.IsType<ElementSelectorInvalid>(Refusal(app, new BlockElement("https://news.example/", "a##b")));
            Assert.Equal("||own-ads.example^\nnews.example##div.promo\nshop.example##.banner",
                app.Query(new GetFilterLists()).CustomFilters);
            Assert.True(app.Query(new PageBlocksElements("https://news.example/")));
            app.Send(new UnblockElements("https://news.example/"));
            Assert.False(app.Query(new PageBlocksElements("https://news.example/")));
            Assert.Equal("||own-ads.example^\nshop.example##.banner", app.Query(new GetFilterLists()).CustomFilters);
            app.Send(new RemoveCustomFilterList(listId));
            Assert.Empty(app.Query(new GetFilterLists()).CustomLists);

            app.Send(new SetSiteContentBlocking(space, site, Blocks: true));
            Assert.True(app.Query(new ContentBlockingApplies(space, site)));
            Assert.Empty(app.Query(new GetSiteContentBlocking()));
        }
    }

    [Fact]
    public void BlockElementRefusesASelectorThatCouldWriteAnotherRule() {
        using var directory = new StorageDirectory();
        var (app, _, _) = DeviceApp(directory);
        using var disposal = app;
        // A page chooses the selector, so nothing in it may end the rule and
        // start another: a scriptlet, a network rule, another separator.
        string[] hostile = [
            "div\n||ads.example^", "div\u2028||ads.example^", "div\u2029x##+js(set, a, 1)", "div\r*##+js(trusted-set, a, 1)",
            "+js(trusted-set, a, 1)", "^script:has-text(ads)", "div##+js(set, a, 1)", "div#@#.promo", "div#?#.promo",
            "div#$#.promo { display: block }", new string('a', ElementRule.MaximumSelectorLength + 1)
        ];
        foreach (var selector in hostile)
            Assert.IsType<ElementSelectorInvalid>(Refusal(app, new BlockElement("https://news.example/", selector)));
        Assert.Equal("", app.Query(new GetFilterLists()).CustomFilters);
        app.Send(new BlockElement("https://news.example/", new string('a', ElementRule.MaximumSelectorLength)));
        Assert.True(app.Query(new PageBlocksElements("https://news.example/")));
    }
}
