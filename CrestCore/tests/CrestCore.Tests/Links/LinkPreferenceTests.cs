using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Link preferences are device state: the device store keeps them beside the
/// session, carried once from the document an installed release kept. A link
/// another app hands a window never opens a locked Space, whatever preference
/// names it, and a link followed from a page goes where its tab, its Peek and
/// the preferences send it.
public sealed partial class BrowserContractsTests {
    private static LinkPreferences Links(IReadOnlyList<Change> changes) =>
        Assert.Single(changes.OfType<LinkPreferencesChanged>()).Preferences;

    [Fact]
    public void TheLinkPreferencesAnInstalledReleaseKeptAreAdoptedOnceAndEveryChangeSurvivesARelaunch() {
        using var directory = new StorageDirectory();
        Guid work = Guid.NewGuid(), personal = Guid.NewGuid(), route = Guid.NewGuid(), added = Guid.NewGuid();
        // The document as the release's encoder wrote it: identities wrapped or
        // bare, a modifier this build does not know, a repeated route identity,
        // a route that does not read, and a key the release had not written yet.
        string document = $$$"""
            {"externalLinkDestination":"chosenSpace","externalLinkSpaceID":{"rawValue":"{{{work}}}"},
            "focusesNewTabsOpenedFromLinks":true,"automaticallyOpensPeek":false,"peekClickModifier":"hyper",
            "quickWindowArchivePolicy":"after24Hours","remembersQuickWindowSpaceBySite":true,
            "routes":[
                {"id":"{{{route}}}","isEnabled":false,"match":"exact","pattern":"example.com","destinationSpaceID":{"rawValue":"{{{personal}}}"}},
                {"id":"{{{route}}}","isEnabled":true,"match":"contains","pattern":"again","destinationSpaceID":"{{{work}}}"},
                {"id":"not-an-identity","isEnabled":true,"match":"contains","pattern":"x","destinationSpaceID":"{{{work}}}"}],
            "rememberedQuickWindowSpacesBySite":{"example.org":"{{{personal}}}"}}
            """;
        var expected = LinkPreferences.Default with {
            Destination = ExternalLinkDestination.ChosenSpace,
            DestinationSpaceId = work,
            FocusesNewTabs = true,
            OpensPeekAutomatically = false,
            ArchivePolicy = QuickWindowArchivePolicy.After24Hours,
            Routes = [new(route, false, LinkRouteMatch.Exact, "example.com", personal)],
            RememberedSites = [new("example.org", personal)]
        };
        LinkPreferences edited;
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            Assert.Equal(expected, Links(app.Send(new AdoptLinkPreferences(Encoding.UTF8.GetBytes(document)))));
            // A later adoption carries nothing more and publishes what the store holds.
            Assert.Equal(expected, Links(app.Send(new AdoptLinkPreferences(Encoding.UTF8.GetBytes("""{"dragsLinksToPeek":false}""")))));

            app.Send(new AddLinkRoute(added, work));
            app.Send(new EditLinkRoute(added, IsEnabled: null, Match: null, Pattern: "news", DestinationSpaceId: null));
            app.Send(new MoveLinkRoute(added, -1));
            app.Send(new SetLinkBehavior(LinkBehavior.DragsLinksToPeek, false));
            app.Send(new SetLinkBehavior(LinkBehavior.DimsPageBehindPeek, false));
            app.Send(new ChoosePeekModifier(LinkPeekModifier.Command));
            edited = Links(app.Send(new RememberQuickWindowSpace("https://www.Example.net/a", work)));
            Assert.Equal([added, route], edited.Routes.Select(link => link.Id));
            Assert.Equal(new RememberedSite("example.net", work), edited.RememberedSites[^1]);
            Assert.False(edited.DimsPageBehindPeek);
            Assert.Equal(new LinkRouteExists(added), Assert.Throws<Rejected>(() => app.Send(new AddLinkRoute(added, work))).Rejection);
            Assert.Empty(app.Send(new MoveLinkRoute(added, -1)).OfType<LinkPreferencesChanged>());
            // An edit of a route another edit removed changes nothing else.
            var removed = Guid.NewGuid();
            app.Send(new AddLinkRoute(removed, personal));
            app.Send(new RemoveLinkRoute(removed));
            Assert.Equal(new UnknownLinkRoute(removed), Assert.Throws<Rejected>(() =>
                app.Send(new EditLinkRoute(removed, IsEnabled: false, Match: null, Pattern: null, DestinationSpaceId: null))).Rejection);
        }

        var (relaunched, _, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        Assert.Equal(edited, Links(relaunched.Send(new AdoptLinkPreferences(Encoding.UTF8.GetBytes(document)))));
    }

    [Fact]
    public void ALinkFromAnotherAppNeverOpensALockedSpaceWhateverNamesIt() {
        var session = GuardedSession(withOpenSecondSpace: true);
        var (app, _, _, workspace, window) = PageHost(session);
        using var disposal = app;
        var locked = Identity(session).Space;
        var open = SpaceId(session["spaces"]![1]!);
        app.Send(new ShowSpace(window, open));
        ExternalLinkPlacement Route(string url) => app.Query(new RouteExternalLink([window], url));
        var substituted = new ExternalLinkPlacement(open, OpensQuickWindow: true, SubstitutesForLockedSpace: true, window, OpensWindow: false);

        // A route, the chosen Space and a remembered site each name the locked Space.
        var route = Guid.NewGuid();
        app.Send(new AddLinkRoute(route, locked));
        app.Send(new EditLinkRoute(route, IsEnabled: null, Match: null, Pattern: "example.com", DestinationSpaceId: null));
        Assert.Equal(substituted, Route("https://example.com/a"));
        app.Send(new ChooseExternalLinkDestination(ExternalLinkDestination.ChosenSpace, locked));
        Assert.Equal(substituted, Route("https://example.org/"));
        app.Send(new ChooseExternalLinkDestination(ExternalLinkDestination.QuickWindow, SpaceId: null));
        app.Send(new RememberQuickWindowSpace("https://example.org/", locked));
        Assert.Equal(substituted, Route("https://example.org/b"));

        // Once unlocked, each opens where it names.
        TestGrants.Unlock(app.Send, workspace, locked);
        Assert.Equal(new ExternalLinkPlacement(locked, false, false, window, false), Route("https://example.com/a"));
        Assert.Equal(new ExternalLinkPlacement(locked, true, false, window, false), Route("https://example.org/b"));

        // With every Space locked, the link opens nowhere.
        app.Send(new LockSpace(locked));
        app.Send(new SetSpaceAccess(workspace, open, SpaceAccessPolicy.DeviceOwnerAuthentication));
        Assert.Equal(new ExternalLinkPlacement(null, false, false, null, false), Route("https://example.com/a"));
    }

    [Fact]
    public void ACopiedLinkLeavesOutWhatCrestAndTheMaintainedListCallTrackingUntilTheDeviceTurnsThatOff() {
        using var directory = new StorageDirectory();
        const string article = "https://example.com/article?id=7&utm_source=news&UTM_Medium=email&fbclid=IwAR0&page=2#top";
        const string story = "https://news.example/story?pk_campaign=spring&cmp=ab&cmp=abc1&src=feed&p=1";
        const string cleanedStory = "https://news.example/story?cmp=abc1&src=feed&p=1";
        // A maintained list as its maintainers publish it: filters for every
        // site and for one, an exception that keeps a parameter Crest's own
        // filters remove, a filter only for other loads than a page's, and a
        // line that is not a parameter filter.
        const string list = """
            [Adblock Plus 2.0]
            ! Title: Sample URL tracking filter
            $removeparam=pk_campaign
            $removeparam=/^cmp=[a-z]{2\,}$/
            $removeparam=src,domain=shop.example
            @@||keeps.example^$removeparam=utm_source
            ||news.example^$removeparam=p,xhr
            news.example##.banner
            """;
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            string Copied(string url) => app.Query(new LinkToCopy(url));
            Assert.Equal("https://example.com/article?id=7&page=2#top", Copied(article));
            Assert.Equal("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42", Copied("https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc&t=42"));
            Assert.Equal("https://www.amazon.co.uk/dp/B08N5WRWNW",
                Copied("https://www.amazon.co.uk/Echo-Dot/dp/B08N5WRWNW/ref=sr_1_3?crid=2XQ&keywords=echo&qid=1&sr=8-3#reviews"));
            // A redirect wrapper copies as its destination, cleaned in turn.
            Assert.Equal("https://example.org/a?b=1#c",
                Copied("https://www.google.com/url?sa=t&q=https%3A%2F%2Fexample.org%2Fa%3Fb%3D1%26utm_source%3Dx%23c&ved=2a"));
            Assert.Equal("mailto:someone@example.com?utm_source=news", Copied("mailto:someone@example.com?utm_source=news"));

            // What only the maintained list names stays until a copy of it arrives.
            Assert.Equal(story, Copied(story));
            app.Send(new FilterDownloadFetched(FilterLibrary.LinkTrackingId, list, null, null));
            Assert.Equal(cleanedStory, Copied(story));
            Assert.Equal("https://shop.example/item?id=1", Copied("https://shop.example/item?id=1&src=feed"));
            Assert.Equal("https://keeps.example/?utm_source=news", Copied("https://keeps.example/?utm_source=news&fbclid=IwAR0"));

            Assert.False(Links(app.Send(new SetLinkBehavior(LinkBehavior.CleansCopiedLinks, false))).CleansCopiedLinks);
            Assert.Equal(article, Copied(article));
        }

        var (relaunched, _, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        Assert.Equal(article, relaunched.Query(new LinkToCopy(article)));
        relaunched.Send(new SetLinkBehavior(LinkBehavior.CleansCopiedLinks, true));
        Assert.Equal(cleanedStory, relaunched.Query(new LinkToCopy(story)));
        using var freshDirectory = new StorageDirectory();
        var (fresh, _, _) = DeviceApp(freshDirectory);
        using var freshDisposal = fresh;
        Assert.Equal("https://example.com/article?id=7&page=2#top", fresh.Query(new LinkToCopy(article)));
    }
}
