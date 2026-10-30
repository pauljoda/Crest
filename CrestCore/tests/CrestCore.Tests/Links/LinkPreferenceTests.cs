using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Link preferences are device state: the device store keeps them beside the
/// session, carried once from the document an installed release kept. A link
/// another app hands a window never opens a locked Space, whatever preference
/// names it, and a link followed from a page goes where its tab, its Peek,
/// the preferences and the routes send it.
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
            app.Send(new ChoosePeekModifier(LinkPeekModifier.Command));
            edited = Links(app.Send(new RememberQuickWindowSpace("https://www.Example.net/a", work)));
            Assert.Equal([added, route], edited.Routes.Select(link => link.Id));
            Assert.Equal(new RememberedSite("example.net", work), edited.RememberedSites[^1]);
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
    public void ALinkARouteClaimsOnAPageOpensInANewTabOfTheRoutedSpace() {
        var session = TwoSpaceSession();
        var (first, second) = (SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!));
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var (_, source) = LiveTab(app, engine, workspace, window, first);
        var route = Guid.NewGuid();
        app.Send(new AddLinkRoute(route, second));
        app.Send(new EditLinkRoute(route, IsEnabled: null, Match: null, Pattern: "routed.example", DestinationSpaceId: null));
        var click = new LinkGesture(UserActivated: true, TopLevel: true, ShortcutModifiers.None, MiddleClick: false);
        LinkNavigationAnswer Follow(string url, LinkGesture gesture) => app.Query(new LinkNavigation(source, url, gesture));
        var stays = new LinkNavigationAnswer(LinkNavigationDecision.Navigate, RoutedSpaceId: null);

        // A plain click on a routed link opens a tab in the routed Space, which
        // the platform opens; a link that no route claims loads in place.
        Assert.Equal(new LinkNavigationAnswer(LinkNavigationDecision.ForegroundTab, second), Follow("https://routed.example/a", click));
        Assert.Equal(stays, Follow("https://other.example/", click));
        Assert.Equal(stays, Follow("https://routed.example/a", click with { TopLevel = false }));

        // A link to the site the page already shows stays on it, so browsing
        // a routed site opened in another Space never bounces the window.
        var (_, onSite) = LiveTab(app, engine, workspace, window, first, "https://www.routed.example/home");
        Assert.Equal(stays, app.Query(new LinkNavigation(onSite, "https://routed.example/a", click)));

        // A route to the page's own Space changes nothing, and as the first
        // match it wins: a later route to another Space never takes its place.
        var (_, own) = LiveTab(app, engine, workspace, window, second, "https://second.example/");
        Assert.Equal(stays, app.Query(new LinkNavigation(own, "https://routed.example/a", click)));
        var ownRoute = Guid.NewGuid();
        app.Send(new AddLinkRoute(ownRoute, first));
        app.Send(new EditLinkRoute(ownRoute, IsEnabled: null, Match: null, Pattern: "routed.example", DestinationSpaceId: null));
        app.Send(new MoveLinkRoute(ownRoute, -1));
        Assert.Equal(stays, Follow("https://routed.example/a", click));
        app.Send(new RemoveLinkRoute(ownRoute));

        // A page the engine opened for such a link is not rerouted: it keeps
        // its opener and its tab beside the page that opened it.
        app.Report(engine, new PageOffered(Guid.NewGuid(), ProfileId(session["spaces"]![0]!), source, null, null, "https://routed.example/b", true));
        Assert.Equal(first, Assert.Single(app.Drain().OfType<OfferedPageAdopted>()).SpaceId);

        // A route to a locked Space leaves the link where it was followed, and
        // never unlocks the Space; so does one to a Space being deleted.
        app.Send(new SetSpaceAccess(workspace, second, SpaceAccessPolicy.DeviceOwnerAuthentication));
        app.Send(new LockSpace(second));
        Assert.Equal(stays, Follow("https://routed.example/c", click));
        TestGrants.Unlock(app.Send, workspace, second);
        Assert.Equal(new LinkNavigationAnswer(LinkNavigationDecision.ForegroundTab, second), Follow("https://routed.example/c", click));
        app.Send(new BeginDeletingSpace(workspace, window, second, Guid.NewGuid()));
        app.Drain();
        Assert.Equal(stays, Follow("https://routed.example/d", click));
    }

}
