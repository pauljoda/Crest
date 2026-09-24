using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class LinkPolicyTests {
    private static readonly Guid Work = Guid.Parse("00000000-0000-4000-8000-000000000021");
    private static readonly Guid Personal = Guid.Parse("00000000-0000-4000-8000-000000000022");
    private static readonly Guid Missing = Guid.Parse("00000000-0000-4000-8000-000000000023");

    private static JsonNode Evaluate(JsonObject request) {
        request["version"] = 1;
        return JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
    }

    private static LinkRoute Route(Guid destination, string pattern, LinkRouteMatch? match = null, bool enabled = true) =>
        new(Guid.NewGuid(), enabled, match ?? LinkRouteMatch.Contains, pattern, destination);

    private static ExternalLinkRoute Routing(string url, LinkRoute[] routes,
        ExternalLinkDestination? destination = null, Guid? chosen = null, Guid? remembered = null,
        bool remembers = true, Guid[]? unavailable = null, Guid[]? locked = null) =>
        new(url, new(routes, destination ?? ExternalLinkDestination.QuickWindow, chosen, remembers, remembered), new([Work, Personal], Work, unavailable ?? []),
            locked ?? []);

    private static ExternalLinkPlacement Placement(ExternalLinkRoute route) => new Links().Answer(route);

    private static (bool QuickWindow, Guid Space) Decision(ExternalLinkRoute route) {
        var placement = Placement(route);
        return (placement.OpensQuickWindow, Assert.NotNull(placement.SpaceId));
    }

    private static JsonObject RouteRecord(Guid destination, string pattern) => new() {
        ["id"] = Guid.NewGuid().ToString("D"),
        ["isEnabled"] = true,
        ["match"] = "contains",
        ["pattern"] = pattern,
        ["destinationSpaceID"] = destination.ToString("D")
    };

    /// Link preferences (`crest.link-preferences.v1`) store these sets by
    /// name, so a renamed member would lose a person's choice.
    [Fact]
    public void StoredSpellingsNeverChange() {
        Assert.Equal(["quickWindow", "mostRecentSpace", "chosenSpace"], ExternalLinkDestination.All.Select(destination => destination.Name));
        Assert.Equal(["contains", "exact"], LinkRouteMatch.All.Select(match => match.Name));
        Assert.Equal(["option", "command"], LinkPeekModifier.All.Select(modifier => modifier.Name));
    }

    [Fact]
    public void TheFirstEnabledRouteToAnOpenSpaceWinsAndExactMatchesIgnoreFragmentsAndCase() {
        LinkRoute[] routes = [
            Route(Personal, "EXAMPLE.COM", enabled: false),
            Route(Missing, "example.com"),
            Route(Work, "https://example.com/reference#configured", LinkRouteMatch.Exact),
            Route(Personal, "example.com")];
        Assert.Equal((false, Work), Decision(Routing("https://EXAMPLE.com/reference#visited", routes)));
        Assert.Equal((false, Personal), Decision(Routing("https://example.com/another", routes)));
        // A blank pattern, still being typed, never claims a link.
        Assert.Equal((true, Work), Decision(Routing("https://example.com/", [Route(Personal, "   ")])));
    }

    [Fact]
    public void WithoutARouteTheDestinationPreferenceDecidesAndFallsBackToTheSelectedSpace() {
        Assert.Equal((true, Personal), Decision(Routing("https://example.com", [], remembered: Personal)));
        Assert.Equal((true, Work), Decision(Routing("https://example.com", [], remembered: Personal, remembers: false)));
        Assert.Equal((true, Work), Decision(Routing("https://example.com", [], remembered: Missing)));
        Assert.Equal((false, Work),
            Decision(Routing("https://example.com", [], ExternalLinkDestination.ChosenSpace, chosen: Missing)));
        Assert.Equal((false, Personal),
            Decision(Routing("https://example.com", [], ExternalLinkDestination.ChosenSpace, chosen: Personal)));
        // A Space being deleted is skipped; the next open Space stands in.
        Assert.Equal((false, Personal),
            Decision(Routing("https://example.com", [], ExternalLinkDestination.MostRecentSpace, unavailable: [Work])));
    }

    [Fact]
    public void QuickWindowsRememberSpacesByNormalizedSiteOnlyWhenAllowed() {
        static string? Site(string url, bool remembers = true) => new Links().Answer(new QuickWindowSite(url, remembers)).Site;
        Assert.Equal("example.com", Site("https://www.Example.com/first"));
        Assert.Equal(Site("https://example.com/second"), Site("https://www.example.com/first"));
        Assert.Null(Site("https://example.com/", remembers: false));
        Assert.Null(Site("about:blank"));
    }

    [Fact]
    public void RouteEditsChangeOneFieldAndRespectTheLimits() {
        var id = Guid.NewGuid();
        var created = Evaluate(new() {
            ["operation"] = "links.route_create",
            ["existing"] = new JsonArray(),
            ["id"] = id.ToString("D"),
            ["destinationSpaceID"] = Work.ToString("D")
        })["route"]!;
        Assert.Equal("", created["pattern"]!.GetValue<string>());
        Assert.True(created["isEnabled"]!.GetValue<bool>());
        Assert.Equal("contains", created["match"]!.GetValue<string>());

        var pattern = Evaluate(new() {
            ["operation"] = "links.route_update",
            ["route"] = created.DeepClone(),
            ["field"] = new JsonObject { ["pattern"] = "https://newer.example/reference" }
        })["route"]!;
        var retargeted = Evaluate(new() {
            ["operation"] = "links.route_update",
            ["route"] = pattern.DeepClone(),
            ["field"] = new JsonObject { ["destinationSpaceID"] = Personal.ToString("D") }
        })["route"]!;
        Assert.Equal("https://newer.example/reference", retargeted["pattern"]!.GetValue<string>());
        Assert.Equal(Personal.ToString("D"), retargeted["destinationSpaceID"]!.GetValue<string>());
        Assert.True(retargeted["isEnabled"]!.GetValue<bool>());

        Assert.Equal(BrowserRuleCodes.InvalidLinkRouteEdit, Evaluate(new() {
            ["operation"] = "links.route_update",
            ["route"] = created.DeepClone(),
            ["field"] = new JsonObject { ["pattern"] = "a", ["isEnabled"] = false }
        })["error"]!.GetValue<string>());
        Assert.Equal(BrowserRuleCodes.LinkPatternTooLong, Evaluate(new() {
            ["operation"] = "links.route_update",
            ["route"] = created.DeepClone(),
            ["field"] = new JsonObject { ["pattern"] = new string('a', LinkRoutePolicy.MaximumPatternLength + 1) }
        })["error"]!.GetValue<string>());
        var full = Enumerable.Range(0, LinkRoutePolicy.MaximumRoutes).Select(_ => Guid.NewGuid()).ToArray();
        Assert.Equal(BrowserRuleCodes.LinkRouteLimit, Assert.Throws<BrowserRuleException>(() =>
            LinkRoutePolicy.Create(full, Guid.NewGuid(), Work)).Code);
        Assert.Equal(BrowserRuleCodes.DuplicateLinkRoute, Assert.Throws<BrowserRuleException>(() =>
            LinkRoutePolicy.Create([id], id, Work)).Code);
    }

    [Fact]
    public void MovingARouteIgnoresOutOfBoundsMovesAndUnknownRoutes() {
        Guid a = Guid.NewGuid(), b = Guid.NewGuid(), c = Guid.NewGuid();
        Assert.Equal([b, a, c], LinkRoutePolicy.Move([a, b, c], a, 1));
        Assert.Equal([a, b, c], LinkRoutePolicy.Move([a, b, c], c, 1));
        Assert.Equal([a, b, c], LinkRoutePolicy.Move([a, b, c], a, -1));
        Assert.Equal([a, b, c], LinkRoutePolicy.Move([a, b, c], Guid.NewGuid(), 1));
        Assert.Equal([a, c], LinkRoutePolicy.Remove([a, b, c], b));
        var moved = Evaluate(new() {
            ["operation"] = "links.route_move",
            ["order"] = new JsonArray(a.ToString("D"), b.ToString("D")),
            ["id"] = b.ToString("D"),
            ["offset"] = -1
        })["order"]!.AsArray().Select(value => Guid.Parse(value!.GetValue<string>()));
        Assert.Equal([b, a], moved);
    }

    [Fact]
    public void DeletingASpaceRemovesItsRoutesChosenSpaceAndRememberedSites() {
        Guid kept = Guid.NewGuid(), removed = Guid.NewGuid();
        var result = Evaluate(new() {
            ["operation"] = "links.space_removed",
            ["spaceID"] = Personal.ToString("D"),
            ["routes"] = new JsonArray(
                new JsonObject { ["id"] = removed.ToString("D"), ["destinationSpaceID"] = Personal.ToString("D") },
                new JsonObject { ["id"] = kept.ToString("D"), ["destinationSpaceID"] = Work.ToString("D") }),
            ["chosenSpaceID"] = Personal.ToString("D"),
            ["rememberedSpaceIDs"] = new JsonArray(Work.ToString("D"), Personal.ToString("D"))
        });
        Assert.Equal([kept.ToString("D")], result["retainedRouteIDs"]!.AsArray().Select(value => value!.GetValue<string>()));
        Assert.True(result["clearsChosenSpace"]!.GetValue<bool>());
        Assert.True(result["forgetsRememberedSites"]!.GetValue<bool>());
        var untouched = LinkRoutePolicy.SpaceRemoved(Missing, [(kept, Work)], Work, [Work]);
        Assert.Equal([kept], untouched.RetainedRouteIds);
        Assert.False(untouched.ClearsChosenSpace);
        Assert.False(untouched.ForgetsRememberedSites);
    }

    [Fact]
    public void RouteEditsRejectMalformedRoutes() {
        var bad = RouteRecord(Work, "example.com");
        bad["match"] = "startsWith";
        Assert.Equal(ProtocolErrorCodes.InvalidLinkRouteMatch, Assert.Throws<ProtocolException>(() => Evaluate(new() {
            ["operation"] = "links.route_update",
            ["route"] = bad,
            ["field"] = new JsonObject { ["isEnabled"] = false }
        })).Code);
    }

    [Fact]
    public void AnExternalLinkRoutedToALockedSpaceOpensInAQuickWindowOnAnUnlockedOne() {
        LinkRoute[] routes = [Route(Personal, "example.com")];
        Assert.Equal(new ExternalLinkPlacement(Work, true, true),
            Placement(Routing("https://example.com/", routes, locked: [Personal])));
        // With every Space locked there is nowhere the link may open.
        Assert.Equal(new ExternalLinkPlacement(null, false, false),
            Placement(Routing("https://example.com/", routes, locked: [Personal, Work])));
        // An unlocked routed Space is used as routed.
        Assert.Equal(new ExternalLinkPlacement(Personal, false, false), Placement(Routing("https://example.com/", routes)));
    }
}
