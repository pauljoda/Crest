import Foundation

struct BrowserLinkRoute: Equatable, Identifiable, Sendable {
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
            destinationSpaceID: destinationSpaceID)
    }
}

// MARK: - Codable

/// Link preferences keep routes in the defaults, so a route's Space keeps the
/// stored identity spelling a build before S6.2 reads.
extension BrowserLinkRoute: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case match
        case pattern
        case destinationSpaceID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            match: try container.decode(LinkRouteMatch.self, forKey: .match),
            pattern: try container.decode(String.self, forKey: .pattern),
            destinationSpaceID: try container.decodeIdentity(forKey: .destinationSpaceID))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(match, forKey: .match)
        try container.encode(pattern, forKey: .pattern)
        try container.encodeStoredIdentity(destinationSpaceID, forKey: .destinationSpaceID)
    }
}
