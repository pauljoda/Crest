import Foundation

enum MobileBrowserWindowSceneRoute: Equatable, Sendable {
    case quickWindow(url: URL, spaceID: SpaceID)
    case space(url: URL, spaceID: SpaceID)

    var spaceID: SpaceID {
        switch self {
        case let .quickWindow(_, spaceID), let .space(_, spaceID):
            spaceID
        }
    }

    static func resolve(
        url: URL,
        decision: BrowserLinkRoutingDecision,
        session: BrowserSession
    ) -> MobileBrowserWindowSceneRoute? {
        guard BrowserExternalURLPolicy.accepts(url),
              session.space(id: decision.spaceID) != nil else { return nil }

        switch decision {
        case let .quickWindow(spaceID):
            return .quickWindow(url: url, spaceID: spaceID)
        case let .space(spaceID):
            return .space(url: url, spaceID: spaceID)
        }
    }
}
