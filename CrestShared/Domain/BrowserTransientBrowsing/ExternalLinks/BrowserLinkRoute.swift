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
}
