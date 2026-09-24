import Foundation

struct BrowserLinkRoute: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var isEnabled: Bool
    var match: LinkRouteMatch
    var pattern: String
    var destinationSpaceID: SpaceID

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        match: LinkRouteMatch = .contains,
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
            id: id, isEnabled: isEnabled, match: match, pattern: pattern,
            destinationSpaceID: destinationSpaceID.rawValue)
    }
}
