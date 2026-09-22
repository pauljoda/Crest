import Foundation

/// Where an external link opens, as decided by the core's `links.route` rule.
enum BrowserLinkRoutingDecision: Equatable, Sendable {
    case quickWindow(spaceID: SpaceID)
    case space(SpaceID)

    var spaceID: SpaceID {
        switch self {
        case .quickWindow(let spaceID), .space(let spaceID):
            spaceID
        }
    }
}
