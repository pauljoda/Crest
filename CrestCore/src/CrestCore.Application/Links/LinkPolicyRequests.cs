using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the route-editing and Space-removal policy operations.
/// Identities are lowercase UUID strings; routes use the native record's field
/// names.
internal static class LinkPolicyRequests {
    #region Variables

    private const int MaximumRoutingSpaces = WorkspaceImportPolicy.MaximumSpaces * 2;

    #endregion

    #region Actions - Decoding


    public sealed record RouteCreate(IReadOnlyList<Guid> Existing, Guid Id, Guid DestinationSpaceId) {
        public static RouteCreate Decode(JsonElement request) {
            Members(request, "existing", "id", "destinationSpaceID");
            var existing = LinkCodes.Identities(Element(request, "existing"));
            var id = Protocol.Id(request, "id");
            return new(existing, id, Protocol.Id(request, "destinationSpaceID"));
        }
    }

    public sealed record RouteUpdate(LinkRoute Route, LinkRouteField Field) {
        public static RouteUpdate Decode(JsonElement request) {
            Members(request, "route", "field");
            var route = LinkCodes.Route(Element(request, "route"));
            return new(route, LinkCodes.RouteField(Element(request, "field")));
        }
    }

    public sealed record RouteMove(IReadOnlyList<Guid> Order, Guid Id, int Offset) {
        public static RouteMove Decode(JsonElement request) {
            Members(request, "order", "id", "offset");
            var order = LinkCodes.Identities(Element(request, "order"));
            var id = Protocol.Id(request, "id");
            return new(order, id, Integer(request, "offset"));
        }
    }

    public sealed record RouteRemove(IReadOnlyList<Guid> Order, Guid Id) {
        public static RouteRemove Decode(JsonElement request) {
            Members(request, "order", "id");
            var order = LinkCodes.Identities(Element(request, "order"));
            return new(order, Protocol.Id(request, "id"));
        }
    }

    public sealed record SpaceRemoved(Guid SpaceId, IReadOnlyList<(Guid Id, Guid Destination)> Routes, Guid? ChosenSpaceId,
        IReadOnlyList<Guid> RememberedSpaceIds) {
        public static SpaceRemoved Decode(JsonElement request) {
            Members(request, "spaceID", "routes", "chosenSpaceID", "rememberedSpaceIDs");
            var routes = Element(request, "routes");
            if (routes.GetArrayLength() > LinkRoutePolicy.MaximumRoutes * 2) throw new ProtocolException(ProtocolErrorCodes.LinkRouteBatchLimit);
            var spaceId = Protocol.Id(request, "spaceID");
            var destinations = routes.EnumerateArray().Select(item => {
                Protocol.Members(item, LinkCodes.Id, LinkCodes.DestinationSpaceId);
                return (Protocol.Id(item, LinkCodes.Id), Protocol.Id(item, LinkCodes.DestinationSpaceId));
            }).ToArray();
            var chosen = Protocol.OptionalId(request, "chosenSpaceID");
            return new(spaceId, destinations, chosen, SpaceIdentities(request, "rememberedSpaceIDs"));
        }
    }

    private static Guid[] SpaceIdentities(JsonElement request, string field) {
        var values = Element(request, field);
        if (values.GetArrayLength() > MaximumRoutingSpaces) throw new ProtocolException(ProtocolErrorCodes.LinkRouteBatchLimit);
        return values.EnumerateArray().Select(Protocol.Id).ToArray();
    }

    #endregion
}
