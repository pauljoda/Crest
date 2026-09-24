import Foundation

struct BrowserLinkRoute: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var isEnabled: Bool
    var match: BrowserLinkRouteMatch
    var pattern: String
    var destinationSpaceID: SpaceID

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        match: BrowserLinkRouteMatch = .contains,
        pattern: String,
        destinationSpaceID: SpaceID
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.match = match
        self.pattern = pattern
        self.destinationSpaceID = destinationSpaceID
    }

    /// This route as the core's routing rule reads it.
    var coreRoute: LinkRoute {
        LinkRoute(
            id: id, isEnabled: isEnabled, match: match.coreMatch, pattern: pattern,
            destinationSpaceID: destinationSpaceID.rawValue)
    }
}

enum BrowserLinkRouteMatch:
    String,
    Codable,
    CaseIterable,
    Equatable,
    Identifiable,
    Sendable
{
    case contains
    case exact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contains: "Contains"
        case .exact: "Is Exactly"
        }
    }

    /// The core's kind for this stored match.
    var coreMatch: LinkRouteMatch {
        switch self {
        case .contains: .contains
        case .exact: .exact
        }
    }
}
