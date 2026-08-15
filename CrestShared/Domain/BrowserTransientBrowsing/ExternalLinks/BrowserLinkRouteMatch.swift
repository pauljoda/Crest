import Foundation

enum BrowserLinkRouteMatch: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
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
