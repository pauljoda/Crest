import Foundation

extension BrowserLinkRoute {
    var coreRecord: [String: Any] {
        [
            "id": id.uuidString.lowercased(), "isEnabled": isEnabled, "match": match.rawValue,
            "pattern": pattern, "destinationSpaceID": destinationSpaceID.rawValue.uuidString.lowercased(),
        ]
    }

    init?(coreRecord: [String: Any]) {
        guard let id = (coreRecord["id"] as? String).flatMap(UUID.init(uuidString:)),
            let isEnabled = coreRecord["isEnabled"] as? Bool,
            let match = (coreRecord["match"] as? String).flatMap(BrowserLinkRouteMatch.init(rawValue:)),
            let pattern = coreRecord["pattern"] as? String,
            let destination = (coreRecord["destinationSpaceID"] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        self.init(id: id, isEnabled: isEnabled, match: match, pattern: pattern,
            destinationSpaceID: SpaceID(rawValue: destination))
    }
}

extension BrowserLinkRouteFieldUpdate {
    fileprivate var coreField: [String: Any] {
        switch self {
        case .isEnabled(let value): ["isEnabled": value]
        case .match(let value): ["match": value.rawValue]
        case .pattern(let value): ["pattern": value]
        case .destinationSpaceID(let value): ["destinationSpaceID": value.rawValue.uuidString.lowercased()]
        }
    }
}

/// External-link routing, route editing and Quick Window rules owned by the
/// portable core. The native store keeps the preferences and persists what the
/// core decides.
extension BrowserCorePolicy {
    /// Where an external link opens. A link routed to a Space in
    /// `lockedSpaceIDs` never raises a prompt for another process: the core
    /// substitutes a Quick Window on an unlocked Space. Nil when no Space may
    /// take the link, or when the core cannot answer — the link is then not
    /// opened rather than landing somewhere the rules did not choose.
    static func linkRoutingDecision(for url: URL, preferences: BrowserLinkPreferences, session: BrowserPresentedSession,
        unavailableSpaceIDs: Set<SpaceID>, lockedSpaceIDs: Set<SpaceID> = []) -> BrowserLinkRoutingDecision? {
        let remembered = linkSite(for: url, remembersSpaceBySite: preferences.remembersQuickWindowSpaceBySite)
            .flatMap { preferences.rememberedQuickWindowSpacesBySite[$0] }
        func text(_ id: SpaceID?) -> Any { id.map { $0.rawValue.uuidString.lowercased() } ?? NSNull() }
        guard let response = evaluate([
            "version": 1, "operation": "links.route", "url": url.absoluteString,
            "routes": preferences.routes.map(\.coreRecord),
            "destination": preferences.externalLinkDestination.rawValue,
            "chosenSpaceID": text(preferences.externalLinkSpaceID),
            "remembersSpaceBySite": preferences.remembersQuickWindowSpaceBySite,
            "rememberedSpaceID": text(remembered),
            "spaces": session.spaces.map { $0.id.rawValue.uuidString.lowercased() },
            "selectedSpaceID": text(session.selectedSpaceID),
            "unavailableSpaceIDs": unavailableSpaceIDs.map { $0.rawValue.uuidString.lowercased() },
            "lockedSpaceIDs": lockedSpaceIDs.map { $0.rawValue.uuidString.lowercased() },
        ]), let quickWindow = response["quickWindow"] as? Bool,
            let space = (response["spaceID"] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        let spaceID = SpaceID(rawValue: space)
        return quickWindow ? .quickWindow(spaceID: spaceID) : .space(spaceID)
    }

    /// The site key a Quick Window remembers its Space under, or nil when the
    /// preference is off, the address has no host, or the core cannot answer.
    static func linkSite(for url: URL, remembersSpaceBySite: Bool) -> String? {
        evaluate(["version": 1, "operation": "links.site", "url": url.absoluteString,
            "remembersSpaceBySite": remembersSpaceBySite])?["site"] as? String
    }

    /// A new route for the settings list. Nil at the route limit or when the
    /// core cannot answer, so nothing is added.
    static func createdLinkRoute(existing: [BrowserLinkRoute], destinationSpaceID: SpaceID) -> BrowserLinkRoute? {
        (evaluate([
            "version": 1, "operation": "links.route_create",
            "existing": existing.map { $0.id.uuidString.lowercased() },
            "id": UUID().uuidString.lowercased(), "destinationSpaceID": destinationSpaceID.rawValue.uuidString.lowercased(),
        ])?["route"] as? [String: Any]).flatMap(BrowserLinkRoute.init(coreRecord:))
    }

    /// The route with one field changed. Nil keeps the route as it was.
    static func updatedLinkRoute(_ route: BrowserLinkRoute, field: BrowserLinkRouteFieldUpdate) -> BrowserLinkRoute? {
        guard let updated = (evaluate(["version": 1, "operation": "links.route_update", "route": route.coreRecord,
            "field": field.coreField])?["route"] as? [String: Any]).flatMap(BrowserLinkRoute.init(coreRecord:)),
            updated.id == route.id else { return nil }
        return updated
    }

    /// Routes after moving one by an offset. Nil keeps the current order.
    static func movingLinkRoute(_ id: UUID, by offset: Int, in routes: [BrowserLinkRoute]) -> [BrowserLinkRoute]? {
        linkRoutes(routes, retaining: evaluate(["version": 1, "operation": "links.route_move",
            "order": routes.map { $0.id.uuidString.lowercased() }, "id": id.uuidString.lowercased(), "offset": offset])?["order"])
    }

    /// Routes without one route. Nil keeps the routes unchanged.
    static func removingLinkRoute(_ id: UUID, from routes: [BrowserLinkRoute]) -> [BrowserLinkRoute]? {
        linkRoutes(routes, retaining: evaluate(["version": 1, "operation": "links.route_remove",
            "order": routes.map { $0.id.uuidString.lowercased() }, "id": id.uuidString.lowercased()])?["order"])
    }

    /// The preferences once a Space is deleted: its routes removed, the chosen
    /// Space cleared, and sites that remembered it forgotten. Nil keeps them;
    /// routing already skips a Space that no longer exists.
    static func linkPreferences(_ preferences: BrowserLinkPreferences, removingSpace spaceID: SpaceID) -> BrowserLinkPreferences? {
        guard let response = evaluate([
            "version": 1, "operation": "links.space_removed", "spaceID": spaceID.rawValue.uuidString.lowercased(),
            "routes": preferences.routes.map {
                ["id": $0.id.uuidString.lowercased(), "destinationSpaceID": $0.destinationSpaceID.rawValue.uuidString.lowercased()]
            },
            "chosenSpaceID": preferences.externalLinkSpaceID.map { $0.rawValue.uuidString.lowercased() } as Any? ?? NSNull(),
            "rememberedSpaceIDs": Set(preferences.rememberedQuickWindowSpacesBySite.values).map { $0.rawValue.uuidString.lowercased() },
        ]), let routes = linkRoutes(preferences.routes, retaining: response["retainedRouteIDs"]),
            let clearsChosenSpace = response["clearsChosenSpace"] as? Bool,
            let forgetsSites = response["forgetsRememberedSites"] as? Bool
        else { return nil }
        var revised = preferences
        revised.routes = routes
        if clearsChosenSpace { revised.externalLinkSpaceID = nil }
        if forgetsSites { revised.rememberedQuickWindowSpacesBySite = revised.rememberedQuickWindowSpacesBySite.filter { $0.value != spaceID } }
        return revised
    }

    /// Seconds before an inactive Quick Window archives itself. Nil never
    /// archives, which is also the answer when the core cannot decide.
    static func quickWindowArchiveLifetime(_ policy: BrowserQuickWindowArchivePolicy) -> TimeInterval? {
        (evaluate(["version": 1, "operation": "quick_window.archive_lifetime", "policy": policy.rawValue])?["lifetime"]
            as? NSNumber)?.doubleValue
    }

    /// Whether dismissing a Quick Window files its page in the archive. A core
    /// that cannot answer archives nothing: no durable record is written
    /// without the core's rule, and the archive command would refuse anyway.
    static func quickWindowArchivesOnDismissal(wasArchived: Bool, wasPromoted: Bool, hasPage: Bool) -> Bool {
        evaluate(["version": 1, "operation": "quick_window.dismissal", "wasArchived": wasArchived,
            "wasPromoted": wasPromoted, "hasPage": hasPage])?["archives"] as? Bool ?? false
    }

    /// Whether moving a Quick Window to `url` in `assignment` revises its
    /// request, and whether the move remembers the Space for the page's site.
    /// `pageURL` is nil for an empty lookup. A core that cannot answer leaves
    /// the request as it was and remembers nothing.
    static func quickWindowRetarget(_ request: BrowserQuickWindowRequest, to url: URL,
        assignment: BrowserSpaceRuntimeAssignment, pageURL: URL?) -> (revises: Bool, remembersSpace: Bool) {
        func placement(_ url: URL, _ assignment: BrowserSpaceRuntimeAssignment) -> [String: Any] {
            ["url": url.absoluteString, "spaceID": assignment.spaceID.rawValue.uuidString.lowercased(),
             "profileID": assignment.profileID.uuidString.lowercased()]
        }
        guard let response = evaluate([
            "version": 1, "operation": "quick_window.retarget",
            "current": placement(request.url, request.assignment), "next": placement(url, assignment),
            "pageURL": pageURL?.absoluteString as Any? ?? NSNull(),
        ]), let revises = response["revises"] as? Bool, let remembers = response["remembersSpace"] as? Bool
        else { return (false, false) }
        return (revises, remembers)
    }

    /// The routes named by the core's identities, in its order. Nil when an
    /// identity is not one of the routes supplied.
    private static func linkRoutes(_ routes: [BrowserLinkRoute], retaining value: Any?) -> [BrowserLinkRoute]? {
        guard let identities = value as? [String] else { return nil }
        let byID = Dictionary(routes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = identities.compactMap { UUID(uuidString: $0).flatMap { byID[$0] } }
        return ordered.count == identities.count ? ordered : nil
    }
}
