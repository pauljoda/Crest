using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Variables

    private const int MaximumRoutingSpaces = WorkspaceImportPolicy.MaximumSpaces * 2;

    #endregion

    #region Actions - Links

    /// Null when the operation is not a link routing or route-editing policy.
    /// Identities are lowercase UUID strings; routes use the native record's
    /// field names. Rule violations answer `{"error":code}`.
    private static JsonObject? EvaluateLinks(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.LinksRoute:
                Protocol.Members(request, "version", "operation", "url", "routes", "destination", "chosenSpaceID",
                    "remembersSpaceBySite", "rememberedSpaceID", "spaces", "selectedSpaceID", "unavailableSpaceIDs");
                var decision = LinkRoutingPolicy.Decide(Protocol.Text(request, "url"),
                    new(LinkCodes.Routes(request.GetProperty("routes")), LinkCodes.Destination(request.GetProperty("destination")),
                        Protocol.OptionalId(request, "chosenSpaceID"), request.GetProperty("remembersSpaceBySite").GetBoolean(),
                        Protocol.OptionalId(request, "rememberedSpaceID")),
                    new(SpaceIdentities(request, "spaces"), Protocol.Id(request, "selectedSpaceID"),
                        SpaceIdentities(request, "unavailableSpaceIDs").ToHashSet()));
                return new() { ["quickWindow"] = decision.OpensQuickWindow, ["spaceID"] = decision.SpaceId.ToString("D") };
            case PolicyOperation.LinksSite:
                Protocol.Members(request, "version", "operation", "url", "remembersSpaceBySite");
                return new() {
                    ["site"] = request.GetProperty("remembersSpaceBySite").GetBoolean()
                        ? LinkRoutingPolicy.Site(Protocol.Text(request, "url")) : null
                };
            case PolicyOperation.LinksRouteCreate:
                Protocol.Members(request, "version", "operation", "existing", "id", "destinationSpaceID");
                return RouteEdit(() => LinkRoutePolicy.Create(LinkCodes.Identities(request.GetProperty("existing")),
                    Protocol.Id(request, "id"), Protocol.Id(request, "destinationSpaceID")));
            case PolicyOperation.LinksRouteUpdate:
                Protocol.Members(request, "version", "operation", "route", "field");
                var route = LinkCodes.Route(request.GetProperty("route"));
                var field = RouteField(request.GetProperty("field"));
                return RouteEdit(() => LinkRoutePolicy.Update(route, field));
            case PolicyOperation.LinksRouteMove:
                Protocol.Members(request, "version", "operation", "order", "id", "offset");
                return new() {
                    ["order"] = LinkCodes.Identities(LinkRoutePolicy.Move(LinkCodes.Identities(request.GetProperty("order")),
                        Protocol.Id(request, "id"), request.GetProperty("offset").GetInt32()))
                };
            case PolicyOperation.LinksRouteRemove:
                Protocol.Members(request, "version", "operation", "order", "id");
                return new() {
                    ["order"] = LinkCodes.Identities(LinkRoutePolicy.Remove(LinkCodes.Identities(request.GetProperty("order")),
                        Protocol.Id(request, "id")))
                };
            case PolicyOperation.LinksSpaceRemoved:
                Protocol.Members(request, "version", "operation", "spaceID", "routes", "chosenSpaceID", "rememberedSpaceIDs");
                var routes = request.GetProperty("routes");
                if (routes.GetArrayLength() > LinkRoutePolicy.MaximumRoutes * 2) throw new ProtocolException(ProtocolErrorCodes.LinkRouteBatchLimit);
                var removal = LinkRoutePolicy.SpaceRemoved(Protocol.Id(request, "spaceID"),
                    routes.EnumerateArray().Select(item => {
                        Protocol.Members(item, LinkCodes.Id, LinkCodes.DestinationSpaceId);
                        return (Protocol.Id(item, LinkCodes.Id), Protocol.Id(item, LinkCodes.DestinationSpaceId));
                    }).ToArray(),
                    Protocol.OptionalId(request, "chosenSpaceID"), SpaceIdentities(request, "rememberedSpaceIDs"));
                return new() {
                    ["retainedRouteIDs"] = LinkCodes.Identities(removal.RetainedRouteIds),
                    ["clearsChosenSpace"] = removal.ClearsChosenSpace,
                    ["forgetsRememberedSites"] = removal.ForgetsRememberedSites
                };
            default:
                return null;
        }
    }

    private static JsonObject RouteEdit(Func<LinkRoute> edit) {
        try {
            return new() { ["route"] = LinkCodes.Route(edit()) };
        } catch (BrowserRuleException error) {
            // The settings editor keeps the person's last accepted value.
            return new() { ["error"] = error.Code };
        }
    }

    private static LinkRouteField RouteField(JsonElement value) {
        Protocol.Members(value, LinkCodes.IsEnabled, LinkCodes.Match, LinkCodes.Pattern, LinkCodes.DestinationSpaceId);
        return new(Optional(value, LinkCodes.IsEnabled)?.GetBoolean(),
            Optional(value, LinkCodes.Match) is { } match ? LinkCodes.RouteMatch(match) : null,
            Optional(value, LinkCodes.Pattern) is { } pattern ? LinkCodes.PatternText(pattern) : null,
            Protocol.OptionalId(value, LinkCodes.DestinationSpaceId));
    }

    private static Guid[] SpaceIdentities(JsonElement request, string field) {
        var values = request.GetProperty(field);
        if (values.GetArrayLength() > MaximumRoutingSpaces) throw new ProtocolException(ProtocolErrorCodes.LinkRouteBatchLimit);
        return values.EnumerateArray().Select(Protocol.Id).ToArray();
    }

    #endregion
}
