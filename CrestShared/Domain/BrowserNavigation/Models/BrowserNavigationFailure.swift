import Foundation

struct BrowserNavigationFailure: Equatable, Sendable {
    /// Why the navigation failed, in the terms the core and every engine share.
    let kind: NavigationError
    let phase: BrowserNavigationFailurePhase
    let failingURL: URL?
    let errorDomain: String
    let errorCode: Int
}

enum BrowserNavigationFailurePhase: Equatable, Sendable {
    case provisional
    case committed
}
