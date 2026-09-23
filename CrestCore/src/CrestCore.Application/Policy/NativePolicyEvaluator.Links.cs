using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.LinkPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Links

    /// Null when the operation is not a link routing or route-editing policy.
    /// Route-edit rule violations answer `{"error":code}`; `spaceID` is null
    /// when no unlocked Space can take a routed link.
    private static JsonObject? EvaluateLinks(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.LinksRoute => RouteLink(Requests.Route.Decode(request)),
        PolicyOperation.LinksSite => LinkCodes.SiteAnswer(Requests.Site.Decode(request).Url is { } url
            ? LinkRoutingPolicy.Site(url) : null),
        PolicyOperation.LinksRouteCreate => CreateRoute(Requests.RouteCreate.Decode(request)),
        PolicyOperation.LinksRouteUpdate => UpdateRoute(Requests.RouteUpdate.Decode(request)),
        PolicyOperation.LinksRouteMove => MoveRoute(Requests.RouteMove.Decode(request)),
        PolicyOperation.LinksRouteRemove => RemoveRoute(Requests.RouteRemove.Decode(request)),
        PolicyOperation.LinksSpaceRemoved => RemoveRouteSpace(Requests.SpaceRemoved.Decode(request)),
        _ => null
    };

    private static JsonObject RouteLink(Requests.Route request) => LinkCodes.RoutingAnswer(
        LinkRoutingPolicy.DecideExternal(request.Url, request.Preferences, request.Context, request.Locked));

    private static JsonObject CreateRoute(Requests.RouteCreate request) =>
        RouteEdit(() => LinkRoutePolicy.Create(request.Existing, request.Id, request.DestinationSpaceId));

    private static JsonObject UpdateRoute(Requests.RouteUpdate request) =>
        RouteEdit(() => LinkRoutePolicy.Update(request.Route, request.Field));

    private static JsonObject MoveRoute(Requests.RouteMove request) =>
        LinkCodes.OrderAnswer(LinkRoutePolicy.Move(request.Order, request.Id, request.Offset));

    private static JsonObject RemoveRoute(Requests.RouteRemove request) =>
        LinkCodes.OrderAnswer(LinkRoutePolicy.Remove(request.Order, request.Id));

    private static JsonObject RemoveRouteSpace(Requests.SpaceRemoved request) => LinkCodes.RemovalAnswer(
        LinkRoutePolicy.SpaceRemoved(request.SpaceId, request.Routes, request.ChosenSpaceId, request.RememberedSpaceIds));

    private static JsonObject RouteEdit(Func<LinkRoute> edit) {
        try {
            return LinkCodes.RouteAnswer(edit());
        } catch (BrowserRuleException error) {
            // The settings editor keeps the person's last accepted value.
            return PolicyAnswers.Error(error);
        }
    }

    #endregion
}
