import Foundation

enum BrowserLinkRoutingDecision: Equatable, Sendable {
    case quickWindow(spaceID: SpaceID)
    case space(SpaceID)

    var spaceID: SpaceID {
        switch self {
        case let .quickWindow(spaceID), let .space(spaceID):
            spaceID
        }
    }
}
