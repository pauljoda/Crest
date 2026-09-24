import Foundation

/// A link route as the core's route operations spell it: identities in their
/// lowercase core spelling.
struct BrowserCoreLinkRouteRecord: Codable, Sendable {
    // MARK: - Variables

    let id: UUID
    let isEnabled: Bool
    let match: BrowserLinkRouteMatch
    let pattern: String
    let destinationSpaceID: UUID

    var route: BrowserLinkRoute {
        BrowserLinkRoute(
            id: id, isEnabled: isEnabled, match: match, pattern: pattern,
            destinationSpaceID: SpaceID(rawValue: destinationSpaceID))
    }

    // MARK: - Initializers

    init(_ route: BrowserLinkRoute) {
        id = route.id
        isEnabled = route.isEnabled
        match = route.match
        pattern = route.pattern
        destinationSpaceID = route.destinationSpaceID.rawValue
    }
}

extension BrowserCoreLinkRouteRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case match
        case pattern
        case destinationSpaceID
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.coreIdentifier, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(match, forKey: .match)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(destinationSpaceID.coreIdentifier, forKey: .destinationSpaceID)
    }
}

/// Route editing and Quick Window rules owned by the portable core. The native
/// store keeps the preferences and persists what the core decides; routing an
/// external link is the typed `ExternalLinkRoute` query.
extension BrowserCorePolicy {
    // MARK: - Types

    /// One changed route field, as the only member of the core's `field`.
    private struct RouteField: Encodable {
        private enum CodingKeys: String, CodingKey {
            case isEnabled
            case match
            case pattern
            case destinationSpaceID
        }

        let update: BrowserLinkRouteFieldUpdate

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch update {
            case .isEnabled(let value): try container.encode(value, forKey: .isEnabled)
            case .match(let value): try container.encode(value, forKey: .match)
            case .pattern(let value): try container.encode(value, forKey: .pattern)
            case .destinationSpaceID(let value):
                try container.encode(value.rawValue.coreIdentifier, forKey: .destinationSpaceID)
            }
        }
    }

    private struct RouteCreateRequest: Encodable {
        let existing: [String]
        let id: String
        let destinationSpaceID: String
    }

    private struct RouteUpdateRequest: Encodable {
        let route: BrowserCoreLinkRouteRecord
        let field: RouteField
    }

    private struct RouteRecordAnswer: Decodable {
        @BrowserCoreOptional var route: BrowserCoreLinkRouteRecord?
    }

    private struct RouteMoveRequest: Encodable {
        let order: [String]
        let id: String
        var offset: Int?
    }

    private struct RouteOrderAnswer: Decodable {
        @BrowserCoreOptional var order: [String]?
    }

    private struct SpaceRemovedRequest: Encodable {
        struct Route: Encodable {
            let id: String
            let destinationSpaceID: String
        }

        let spaceID: String
        let routes: [Route]
        @BrowserCoreNullable var chosenSpaceID: String?
        let rememberedSpaceIDs: [String]
    }

    private struct SpaceRemovedAnswer: Decodable {
        @BrowserCoreOptional var retainedRouteIDs: [String]?
        let clearsChosenSpace: Bool
        let forgetsRememberedSites: Bool
    }

    private struct ArchiveLifetimeRequest: Encodable {
        let policy: BrowserQuickWindowArchivePolicy
    }

    private struct ArchiveLifetimeAnswer: Decodable {
        @BrowserCoreOptional var lifetime: TimeInterval?
    }

    private struct QuickWindowDismissalRequest: Encodable {
        let wasArchived: Bool
        let wasPromoted: Bool
        let hasPage: Bool
    }

    private struct QuickWindowDismissalAnswer: Decodable {
        @BrowserCoreOptional var archives: Bool?
    }

    private struct RetargetRequest: Encodable {
        struct Placement: Encodable {
            let url: String
            let spaceID: String
            let profileID: String

            init(_ url: URL, _ assignment: BrowserSpaceRuntimeAssignment) {
                self.url = url.absoluteString
                spaceID = assignment.spaceID.rawValue.coreIdentifier
                profileID = assignment.profileID.coreIdentifier
            }
        }

        let current: Placement
        let next: Placement
        @BrowserCoreNullable var pageURL: String?
    }

    private struct RetargetAnswer: Decodable {
        let revises: Bool
        let remembersSpace: Bool
    }

    // MARK: - Actions - Route editing

    /// A new route for the settings list. Nil at the route limit or when the
    /// core cannot answer, so nothing is added.
    static func createdLinkRoute(existing: [BrowserLinkRoute], destinationSpaceID: SpaceID) -> BrowserLinkRoute? {
        let request = RouteCreateRequest(
            existing: existing.map { $0.id.coreIdentifier }, id: UUID().coreIdentifier,
            destinationSpaceID: destinationSpaceID.rawValue.coreIdentifier)
        return evaluate(.linksRouteCreate, request, answer: RouteRecordAnswer.self)?.route?.route
    }

    /// The route with one field changed. Nil keeps the route as it was.
    static func updatedLinkRoute(_ route: BrowserLinkRoute, field: BrowserLinkRouteFieldUpdate) -> BrowserLinkRoute? {
        let request = RouteUpdateRequest(route: BrowserCoreLinkRouteRecord(route), field: RouteField(update: field))
        guard let updated = evaluate(.linksRouteUpdate, request, answer: RouteRecordAnswer.self)?.route?.route,
            updated.id == route.id
        else { return nil }
        return updated
    }

    /// Routes after moving one by an offset. Nil keeps the current order.
    static func movingLinkRoute(_ id: UUID, by offset: Int, in routes: [BrowserLinkRoute]) -> [BrowserLinkRoute]? {
        let request = RouteMoveRequest(
            order: routes.map { $0.id.coreIdentifier }, id: id.coreIdentifier, offset: offset)
        return linkRoutes(routes, retaining: evaluate(.linksRouteMove, request, answer: RouteOrderAnswer.self)?.order)
    }

    /// Routes without one route. Nil keeps the routes unchanged.
    static func removingLinkRoute(_ id: UUID, from routes: [BrowserLinkRoute]) -> [BrowserLinkRoute]? {
        let request = RouteMoveRequest(order: routes.map { $0.id.coreIdentifier }, id: id.coreIdentifier)
        return linkRoutes(routes, retaining: evaluate(.linksRouteRemove, request, answer: RouteOrderAnswer.self)?.order)
    }

    /// The preferences once a Space is deleted: its routes removed, the chosen
    /// Space cleared, and sites that remembered it forgotten. Nil keeps them;
    /// routing already skips a Space that no longer exists.
    static func linkPreferences(_ preferences: BrowserLinkPreferences, removingSpace spaceID: SpaceID)
        -> BrowserLinkPreferences?
    {
        let request = SpaceRemovedRequest(
            spaceID: spaceID.rawValue.coreIdentifier,
            routes: preferences.routes.map {
                SpaceRemovedRequest.Route(
                    id: $0.id.coreIdentifier, destinationSpaceID: $0.destinationSpaceID.rawValue.coreIdentifier)
            },
            chosenSpaceID: preferences.externalLinkSpaceID?.rawValue.coreIdentifier,
            rememberedSpaceIDs: Set(preferences.rememberedQuickWindowSpacesBySite.values).map {
                $0.rawValue.coreIdentifier
            })
        guard let answer = evaluate(.linksSpaceRemoved, request, answer: SpaceRemovedAnswer.self),
            let routes = linkRoutes(preferences.routes, retaining: answer.retainedRouteIDs)
        else { return nil }
        var revised = preferences
        revised.routes = routes
        if answer.clearsChosenSpace { revised.externalLinkSpaceID = nil }
        if answer.forgetsRememberedSites {
            revised.rememberedQuickWindowSpacesBySite = revised.rememberedQuickWindowSpacesBySite.filter {
                $0.value != spaceID
            }
        }
        return revised
    }

    // MARK: - Actions - Quick Windows

    /// Seconds before an inactive Quick Window archives itself. Nil never
    /// archives, which is also the answer when the core cannot decide.
    static func quickWindowArchiveLifetime(_ policy: BrowserQuickWindowArchivePolicy) -> TimeInterval? {
        evaluate(
            .quickWindowArchiveLifetime, ArchiveLifetimeRequest(policy: policy), answer: ArchiveLifetimeAnswer.self)?
            .lifetime
    }

    /// Whether dismissing a Quick Window files its page in the archive. A core
    /// that cannot answer archives nothing: no durable record is written
    /// without the core's rule, and the archive command would refuse anyway.
    static func quickWindowArchivesOnDismissal(wasArchived: Bool, wasPromoted: Bool, hasPage: Bool) -> Bool {
        let request = QuickWindowDismissalRequest(wasArchived: wasArchived, wasPromoted: wasPromoted, hasPage: hasPage)
        return evaluate(.quickWindowDismissal, request, answer: QuickWindowDismissalAnswer.self)?.archives ?? false
    }

    /// Whether moving a Quick Window to `url` in `assignment` revises its
    /// request, and whether the move remembers the Space for the page's site.
    /// `pageURL` is nil for an empty lookup. A core that cannot answer leaves
    /// the request as it was and remembers nothing.
    static func quickWindowRetarget(
        _ request: BrowserQuickWindowRequest, to url: URL,
        assignment: BrowserSpaceRuntimeAssignment, pageURL: URL?
    ) -> (revises: Bool, remembersSpace: Bool) {
        let retarget = RetargetRequest(
            current: RetargetRequest.Placement(request.url, request.assignment),
            next: RetargetRequest.Placement(url, assignment), pageURL: pageURL?.absoluteString)
        guard let answer = evaluate(.quickWindowRetarget, retarget, answer: RetargetAnswer.self) else {
            return (false, false)
        }
        return (answer.revises, answer.remembersSpace)
    }

    /// The routes named by the core's identities, in its order. Nil when an
    /// identity is not one of the routes supplied.
    private static func linkRoutes(_ routes: [BrowserLinkRoute], retaining identities: [String]?) -> [BrowserLinkRoute]?
    {
        guard let identities else { return nil }
        let byID = Dictionary(routes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = identities.compactMap { UUID(uuidString: $0).flatMap { byID[$0] } }
        return ordered.count == identities.count ? ordered : nil
    }
}
