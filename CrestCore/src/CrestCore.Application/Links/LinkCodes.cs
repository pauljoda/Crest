using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for link routes, shared by the route-editing policy
/// operations. Values use the native preference record's spellings.
internal static class LinkCodes {
    #region Variables

    public const string Id = "id";
    public const string IsEnabled = "isEnabled";
    public const string Match = "match";
    public const string Pattern = "pattern";
    public const string DestinationSpaceId = "destinationSpaceID";

    #endregion

    #region Actions - Decoding

    public static LinkRoute Route(JsonElement value) {
        Protocol.Members(value, Id, IsEnabled, Match, Pattern, DestinationSpaceId);
        return new(Protocol.Id(value, Id), value.GetProperty(IsEnabled).GetBoolean(), RouteMatch(value.GetProperty(Match)),
            PatternText(value.GetProperty(Pattern)), Protocol.Id(value, DestinationSpaceId));
    }

    /// A route edit names exactly the fields it changes.
    public static LinkRouteField RouteField(JsonElement value) {
        Protocol.Members(value, IsEnabled, Match, Pattern, DestinationSpaceId);
        return new(PolicyFields.OptionalFlag(value, IsEnabled),
            PolicyFields.Optional(value, Match) is { } match ? RouteMatch(match) : null,
            PolicyFields.Optional(value, Pattern) is { } pattern ? PatternText(pattern) : null,
            Protocol.OptionalId(value, DestinationSpaceId));
    }

    public static IReadOnlyList<Guid> Identities(JsonElement value) {
        if (value.GetArrayLength() > LinkRoutePolicy.MaximumRoutes * 2) throw new ProtocolException(ProtocolErrorCodes.LinkRouteBatchLimit);
        return value.EnumerateArray().Select(Protocol.Id).ToArray();
    }

    public static LinkRouteMatch RouteMatch(JsonElement value) => value.GetString() switch {
        "contains" => LinkRouteMatch.Contains,
        "exact" => LinkRouteMatch.Exact,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidLinkRouteMatch)
    };


    /// A pattern the person may still be typing, so it may be empty. The
    /// domain rejects one that is too long.
    public static string PatternText(JsonElement value) {
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { } text
            || text.Length > LinkRoutePolicy.MaximumPatternLength * 2)
            throw new ProtocolException(ProtocolErrorCodes.InvalidString);
        return text;
    }

    #endregion

    #region Actions - Encoding

    public static JsonObject Route(LinkRoute route) => new() {
        [Id] = route.Id.ToString("D"),
        [IsEnabled] = route.IsEnabled,
        [Match] = route.Match == LinkRouteMatch.Exact ? "exact" : "contains",
        [Pattern] = route.Pattern,
        [DestinationSpaceId] = route.DestinationSpaceId.ToString("D")
    };

    public static JsonArray Identities(IEnumerable<Guid> ids) =>
        new(ids.Select(id => (JsonNode?)JsonValue.Create(id.ToString("D"))).ToArray());


    public static JsonObject RouteAnswer(LinkRoute route) => new() { ["route"] = Route(route) };

    public static JsonObject OrderAnswer(IEnumerable<Guid> order) => new() { ["order"] = Identities(order) };

    public static JsonObject RemovalAnswer(LinkSpaceRemoval removal) => new() {
        ["retainedRouteIDs"] = Identities(removal.RetainedRouteIds),
        ["clearsChosenSpace"] = removal.ClearsChosenSpace,
        ["forgetsRememberedSites"] = removal.ForgetsRememberedSites
    };

    #endregion
}
