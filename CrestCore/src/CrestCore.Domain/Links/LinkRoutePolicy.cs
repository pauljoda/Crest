namespace CrestCore.Domain;

/// Editing rules for the ordered link routes and what a deleted Space leaves
/// behind in them. Routes are native preferences; these rules decide every
/// change the native store then persists.
public static class LinkRoutePolicy {
    #region Variables

    public const int MaximumRoutes = 64;
    public const int MaximumPatternLength = 2048;

    #endregion

    #region Actions - Route edits

    /// A new route starts enabled, matching by containment, with an empty
    /// pattern the person fills in; an empty pattern never matches.
    public static LinkRoute Create(IReadOnlyCollection<Guid> existing, Guid id, Guid destinationSpaceId) {
        RequireDistinct(existing);
        if (existing.Count >= MaximumRoutes) throw new BrowserRuleException(BrowserRuleCodes.LinkRouteLimit);
        if (id == Guid.Empty || destinationSpaceId == Guid.Empty || existing.Contains(id))
            throw new BrowserRuleException(BrowserRuleCodes.DuplicateLinkRoute);
        return new(id, true, LinkRouteMatch.Contains, "", destinationSpaceId);
    }

    /// Changes exactly one field, so concurrent edits to other fields of the
    /// same route are never overwritten by a stale copy.
    public static LinkRoute Update(LinkRoute route, LinkRouteField field) {
        int supplied = (field.IsEnabled is null ? 0 : 1) + (field.Match is null ? 0 : 1)
            + (field.Pattern is null ? 0 : 1) + (field.DestinationSpaceId is null ? 0 : 1);
        if (supplied != 1) throw new BrowserRuleException(BrowserRuleCodes.InvalidLinkRouteEdit);
        if (field.Pattern is { Length: > MaximumPatternLength }) throw new BrowserRuleException(BrowserRuleCodes.LinkPatternTooLong);
        if (field.DestinationSpaceId == Guid.Empty) throw new BrowserRuleException(BrowserRuleCodes.InvalidLinkRouteEdit);
        return route with {
            IsEnabled = field.IsEnabled ?? route.IsEnabled,
            Match = field.Match ?? route.Match,
            Pattern = field.Pattern ?? route.Pattern,
            DestinationSpaceId = field.DestinationSpaceId ?? route.DestinationSpaceId
        };
    }

    /// Moves one route by an offset. An unknown route or a move past either end
    /// leaves the order unchanged.
    public static IReadOnlyList<Guid> Move(IReadOnlyList<Guid> order, Guid id, int offset) {
        RequireDistinct(order);
        int source = order.ToList().IndexOf(id);
        long destination = (long)source + offset;
        if (source < 0 || destination < 0 || destination >= order.Count) return order;
        var result = order.ToList();
        result.RemoveAt(source);
        result.Insert((int)destination, id);
        return result;
    }

    public static IReadOnlyList<Guid> Remove(IReadOnlyList<Guid> order, Guid id) {
        RequireDistinct(order);
        return order.Where(route => route != id).ToArray();
    }

    #endregion

    #region Actions - Space deletion

    /// A deleted Space takes its routes with it, stops being the chosen
    /// external-link Space, and is forgotten for every site that remembered it.
    /// Routing already skips missing Spaces; this keeps the stored preferences
    /// from pointing at a Space that no longer exists.
    public static LinkSpaceRemoval SpaceRemoved(Guid spaceId, IReadOnlyList<(Guid Id, Guid Destination)> routes,
        Guid? chosenSpaceId, IReadOnlyCollection<Guid> rememberedSpaceIds) {
        RequireDistinct(routes.Select(route => route.Id).ToArray());
        return new(routes.Where(route => route.Destination != spaceId).Select(route => route.Id).ToArray(),
            chosenSpaceId == spaceId, rememberedSpaceIds.Contains(spaceId));
    }

    private static void RequireDistinct(IReadOnlyCollection<Guid> ids) {
        if (ids.Count > MaximumRoutes * 2 || ids.Distinct().Count() != ids.Count)
            throw new BrowserRuleException(BrowserRuleCodes.DuplicateLinkRoute);
    }

    #endregion
}
