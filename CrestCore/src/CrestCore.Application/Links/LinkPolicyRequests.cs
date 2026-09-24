using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the route-editing and Space-removal policy operations,
/// and the route record they and their answers share. Identities are lowercase
/// UUID strings; routes use the native record's field names, and a match is
/// spelled as its `Name`.
internal static class LinkPolicyRequests {
    #region Variables

    private const string Id = "id";
    private const string IsEnabled = "isEnabled";
    private const string Match = "match";
    private const string Pattern = "pattern";
    private const string DestinationSpaceId = "destinationSpaceID";
    private const int MaximumRoutingSpaces = WorkspaceImportPolicy.MaximumSpaces * 2;

    #endregion

    #region Actions - Decoding

    public sealed record RouteCreate(IReadOnlyList<Guid> Existing, Guid Id, Guid DestinationSpaceId) {
        public static RouteCreate Decode(JsonElement request) {
            Members(request, "existing", "id", "destinationSpaceID");
            var existing = DecodeIdentities(Element(request, "existing"));
            var id = Protocol.Id(request, "id");
            return new(existing, id, Protocol.Id(request, "destinationSpaceID"));
        }
    }

    public sealed record RouteUpdate(LinkRoute Route, LinkRouteField Field) {
        public static RouteUpdate Decode(JsonElement request) {
            Members(request, "route", "field");
            var route = DecodeRoute(Element(request, "route"));
            return new(route, DecodeRouteField(Element(request, "field")));
        }
    }

    public sealed record RouteMove(IReadOnlyList<Guid> Order, Guid Id, int Offset) {
        public static RouteMove Decode(JsonElement request) {
            Members(request, "order", "id", "offset");
            var order = DecodeIdentities(Element(request, "order"));
            var id = Protocol.Id(request, "id");
            return new(order, id, Integer(request, "offset"));
        }
    }

    public sealed record RouteRemove(IReadOnlyList<Guid> Order, Guid Id) {
        public static RouteRemove Decode(JsonElement request) {
            Members(request, "order", "id");
            var order = DecodeIdentities(Element(request, "order"));
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
                Protocol.Members(item, Id, DestinationSpaceId);
                return (Protocol.Id(item, Id), Protocol.Id(item, DestinationSpaceId));
            }).ToArray();
            var chosen = Protocol.OptionalId(request, "chosenSpaceID");
            return new(spaceId, destinations, chosen, SpaceIdentities(request, "rememberedSpaceIDs"));
        }
    }

    private static LinkRoute DecodeRoute(JsonElement value) {
        Protocol.Members(value, Id, IsEnabled, Match, Pattern, DestinationSpaceId);
        return new(Protocol.Id(value, Id), value.GetProperty(IsEnabled).GetBoolean(), DecodeMatch(value.GetProperty(Match)),
            DecodePattern(value.GetProperty(Pattern)), Protocol.Id(value, DestinationSpaceId));
    }

    /// A route edit names exactly the fields it changes.
    private static LinkRouteField DecodeRouteField(JsonElement value) {
        Protocol.Members(value, IsEnabled, Match, Pattern, DestinationSpaceId);
        return new(OptionalFlag(value, IsEnabled), Optional(value, Match) is { } match ? DecodeMatch(match) : null,
            Optional(value, Pattern) is { } pattern ? DecodePattern(pattern) : null, Protocol.OptionalId(value, DestinationSpaceId));
    }

    private static IReadOnlyList<Guid> DecodeIdentities(JsonElement value) {
        if (value.GetArrayLength() > LinkRoutePolicy.MaximumRoutes * 2) throw new ProtocolException(ProtocolErrorCodes.LinkRouteBatchLimit);
        return value.EnumerateArray().Select(Protocol.Id).ToArray();
    }

    private static LinkRouteMatch DecodeMatch(JsonElement value) =>
        LinkRouteMatch.Named(value.GetString()) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidLinkRouteMatch);

    /// A pattern the person may still be typing, so it may be empty. The
    /// domain rejects one that is too long.
    private static string DecodePattern(JsonElement value) {
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { } text
            || text.Length > LinkRoutePolicy.MaximumPatternLength * 2)
            throw new ProtocolException(ProtocolErrorCodes.InvalidString);
        return text;
    }

    private static Guid[] SpaceIdentities(JsonElement request, string field) {
        var values = Element(request, field);
        if (values.GetArrayLength() > MaximumRoutingSpaces) throw new ProtocolException(ProtocolErrorCodes.LinkRouteBatchLimit);
        return values.EnumerateArray().Select(Protocol.Id).ToArray();
    }

    #endregion

    #region Actions - Encoding

    public static JsonObject EncodeRoute(LinkRoute route) => new() {
        [Id] = route.Id.ToString("D"),
        [IsEnabled] = route.IsEnabled,
        [Match] = route.Match.Name,
        [Pattern] = route.Pattern,
        [DestinationSpaceId] = route.DestinationSpaceId.ToString("D")
    };

    public static JsonArray EncodeIdentities(IEnumerable<Guid> ids) =>
        new(ids.Select(id => (JsonNode?)JsonValue.Create(id.ToString("D"))).ToArray());

    #endregion
}
