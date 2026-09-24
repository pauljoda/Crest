using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using Requests = CrestCore.Application.LinkPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Links

    /// Null when the operation is not a route-editing policy. Route-edit rule
    /// violations answer `{"error":code}`. Routing an external link and the
    /// Quick Window site key are the typed `ExternalLinkRoute` and
    /// `QuickWindowSite` queries.
    private static JsonObject? EvaluateLinks(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.LinksRouteCreate => CreateRoute(Requests.RouteCreate.Decode(request)),
        PolicyOperation.LinksRouteUpdate => UpdateRoute(Requests.RouteUpdate.Decode(request)),
        PolicyOperation.LinksRouteMove => MoveRoute(Requests.RouteMove.Decode(request)),
        PolicyOperation.LinksRouteRemove => RemoveRoute(Requests.RouteRemove.Decode(request)),
        PolicyOperation.LinksSpaceRemoved => RemoveRouteSpace(Requests.SpaceRemoved.Decode(request)),
        _ => null
    };


    private static JsonObject CreateRoute(Requests.RouteCreate request) =>
        RouteEdit(() => LinkRoutePolicy.Create(request.Existing, request.Id, request.DestinationSpaceId));

    private static JsonObject UpdateRoute(Requests.RouteUpdate request) =>
        RouteEdit(() => LinkRoutePolicy.Update(request.Route, request.Field));

    private static JsonObject MoveRoute(Requests.RouteMove request) =>
        new() { ["order"] = Requests.EncodeIdentities(LinkRoutePolicy.Move(request.Order, request.Id, request.Offset)) };

    private static JsonObject RemoveRoute(Requests.RouteRemove request) =>
        new() { ["order"] = Requests.EncodeIdentities(LinkRoutePolicy.Remove(request.Order, request.Id)) };

    private static JsonObject RemoveRouteSpace(Requests.SpaceRemoved request) {
        var removal = LinkRoutePolicy.SpaceRemoved(request.SpaceId, request.Routes, request.ChosenSpaceId, request.RememberedSpaceIds);
        return new() {
            ["retainedRouteIDs"] = Requests.EncodeIdentities(removal.RetainedRouteIds),
            ["clearsChosenSpace"] = removal.ClearsChosenSpace,
            ["forgetsRememberedSites"] = removal.ForgetsRememberedSites
        };
    }

    private static JsonObject RouteEdit(Func<LinkRoute> edit) {
        try {
            return new() { ["route"] = Requests.EncodeRoute(edit()) };
        } catch (BrowserRuleException error) {
            // The settings editor keeps the person's last accepted value.
            return PolicyAnswers.Error(error);
        }
    }

    #endregion
}
