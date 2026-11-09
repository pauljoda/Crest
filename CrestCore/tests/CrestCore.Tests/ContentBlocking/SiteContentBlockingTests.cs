using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Ad blocking holds for every Space alike: the level it blocks at, the
/// lists that level turns on, and the sites where it blocks nothing, which the
/// device store keeps when they were turned off from a persistent Space. It
/// keeps the lists the person added and their own filters too, including the
/// rules Block Element adds per site.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ASiteTurnedOffHoldsInEverySpaceAndTheDeviceKeepsIt() {
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
            Assert.False(app.Query(new ContentBlockingApplies(otherSpace, site)));
            Assert.Empty(app.Send(new SetSiteContentBlocking(space, site, Blocks: false)));
            Assert.Empty(app.Send(new SetSiteContentBlocking(otherSpace, site, Blocks: false)));
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
            Assert.False(app.Query(new ContentBlockingApplies(otherSpace, site)));
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

            // Turning it on again from any Space turns it on everywhere.
            app.Send(new SetSiteContentBlocking(otherSpace, site, Blocks: true));
            Assert.True(app.Query(new ContentBlockingApplies(space, site)));
            Assert.Empty(app.Query(new GetSiteContentBlocking()));
        }
    }

    [Fact]
    public void ALevelSetsTheListsForEverySpaceAndOffBlocksNothing() {
        using var directory = new StorageDirectory();
        var site = new SiteOrigin("https", "news.example", 443);
        Guid space, otherSpace;
        {
            var (app, _, spaces) = DeviceApp(directory);
            using var disposal = app;
            space = SpaceId(spaces[0]!);
            otherSpace = SpaceId(spaces[1]!);
            var lists = app.Query(new GetFilterLists());
            Assert.Equal(ContentBlockingLevel.Balanced, lists.Level);
            Assert.False(lists.IsCustomized);
            Assert.True(IsOn(lists, FilterList.EasyList));
            Assert.False(IsOn(lists, FilterList.AdGuardBase));
            Assert.False(IsOn(lists, FilterList.EasyListCookie));

            var strict = Assert.Single(app.Send(new SetContentBlockingLevel(ContentBlockingLevel.Strict)).OfType<FilterListsChanged>()).Lists;
            Assert.Equal(ContentBlockingLevel.Strict, strict.Level);
            Assert.True(IsOn(strict, FilterList.AdGuardBase) && IsOn(strict, FilterList.EasyListCookie)
                && IsOn(strict, FilterList.AdGuardAnnoyances) && IsOn(strict, FilterList.EasyList));
            Assert.False(strict.IsCustomized);
            Assert.Empty(app.Send(new SetContentBlockingLevel(ContentBlockingLevel.Strict)));

            // Turning a list against the level customizes it; choosing the
            // level again restores its lists.
            Assert.True(Assert.Single(app.Send(new SetFilterList(FilterList.EasyListCookie, IsOn: false))
                .OfType<FilterListsChanged>()).Lists.IsCustomized);
            var restored = Assert.Single(app.Send(new SetContentBlockingLevel(ContentBlockingLevel.Strict))
                .OfType<FilterListsChanged>()).Lists;
            Assert.True(IsOn(restored, FilterList.EasyListCookie));
            Assert.False(restored.IsCustomized);

            // Off blocks nothing in any Space, and keeps the lists beneath it.
            app.Send(new SetFilterList(FilterList.EasyPrivacy, IsOn: false));
            var off = Assert.Single(app.Send(new SetContentBlockingLevel(ContentBlockingLevel.Off)).OfType<FilterListsChanged>()).Lists;
            Assert.False(off.IsCustomized);
            Assert.False(IsOn(off, FilterList.EasyPrivacy));
            Assert.False(app.Query(new ContentBlockingApplies(space, site)));
            Assert.False(app.Query(new ContentBlockingApplies(otherSpace, null)));
            Assert.Equal(CosmeticFilters.None,
                app.Query(new DocumentCosmetics(space, "https://news.example/", "https://news.example/", true, [], [], [])));
            Assert.Equal("", app.Query(new PageScriptlets(space, "https://news.example/")));
        }
        {
            // The device keeps the level and the lists beneath it.
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            var lists = app.Query(new GetFilterLists());
            Assert.Equal(ContentBlockingLevel.Off, lists.Level);
            Assert.False(IsOn(lists, FilterList.EasyPrivacy));
            Assert.False(app.Query(new ContentBlockingApplies(space, site)));
            var balanced = Assert.Single(app.Send(new SetContentBlockingLevel(ContentBlockingLevel.Balanced))
                .OfType<FilterListsChanged>()).Lists;
            Assert.True(IsOn(balanced, FilterList.EasyPrivacy));
            Assert.False(IsOn(balanced, FilterList.AdGuardBase));
            Assert.True(app.Query(new ContentBlockingApplies(otherSpace, site)));
        }
    }

    [Fact]
    public void ADeviceWhoseSpacesAllBlockedNothingStartsOff() {
        using var directory = new StorageDirectory();
        {
            // Before blocking held for every Space, each Space chose for
            // itself; here every Space chose Off before any level was chosen.
            var (app, workspace, _) = DeviceApp(directory);
            using var disposal = app;
            foreach (var each in app.Workspace(workspace).Current.Spaces) {
                var preferences = each.Settings.BrowsingPreferences;
                app.Send(new SetBrowsingPreferences(workspace, each.Id, preferences.CurrentTabCleanup, ContentBlockingPolicy.Off,
                    preferences.DataRetention));
            }
        }
        {
            // Until the persistent Spaces open, the core can only answer
            // Balanced; opening them announces the level they settle on.
            var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
            using var disposal = app;
            Assert.Equal(ContentBlockingLevel.Balanced, app.Query(new GetFilterLists()).Level);
            var (workspace, opened) = TestWorkspaces.OpenStored(app);
            Assert.Equal(ContentBlockingLevel.Off, Assert.Single(opened.OfType<FilterListsChanged>()).Lists.Level);
            Assert.Equal(ContentBlockingLevel.Off, app.Query(new GetFilterLists()).Level);
            Assert.False(app.Query(new ContentBlockingApplies(app.Workspace(workspace).Current.Spaces[0].Id, null)));
            app.Send(new SetContentBlockingLevel(ContentBlockingLevel.Balanced));
        }
        {
            // The level chosen holds, whatever the Spaces once chose.
            var (app, _, spaces) = DeviceApp(directory);
            using var disposal = app;
            Assert.Equal(ContentBlockingLevel.Balanced, app.Query(new GetFilterLists()).Level);
            Assert.True(app.Query(new ContentBlockingApplies(SpaceId(spaces[0]!), null)));
        }
    }

    [Fact]
    public void ASitePrivateBrowsingTurnedOffIsKeptOnceAPersistentSpaceTurnsItOff() {
        using var directory = new StorageDirectory();
        var site = new SiteOrigin("https", "news.example", 443);
        Guid space;
        {
            var (app, _, spaces) = DeviceApp(directory);
            using var disposal = app;
            space = SpaceId(spaces[0]!);
            var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, null)));
            var privateSpace = app.Workspace(privateWorkspace).Current.Spaces[0].Id;
            app.Send(new SetSiteContentBlocking(privateSpace, site, Blocks: false));
            Assert.Equal([new SiteContentBlocking(privateSpace, site)], app.Query(new GetSiteContentBlocking()));
            Assert.Empty(app.Send(new SetSiteContentBlocking(privateSpace, site, Blocks: false)));

            var kept = Assert.Single(app.Send(new SetSiteContentBlocking(space, site, Blocks: false)).OfType<SiteContentBlockingChanged>());
            Assert.Equal([new SiteContentBlocking(space, site)], kept.Sites);
            Assert.Empty(app.Send(new SetSiteContentBlocking(privateSpace, site, Blocks: false)));
        }
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            Assert.Equal([new SiteContentBlocking(space, site)], app.Query(new GetSiteContentBlocking()));
        }
    }

    private static bool IsOn(FilterLists lists, FilterList list) => lists.Lists.Single(state => state.List == list).IsOn;

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
