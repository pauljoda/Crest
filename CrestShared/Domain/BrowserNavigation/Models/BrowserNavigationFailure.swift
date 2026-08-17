import Foundation

struct BrowserNavigationFailure: Equatable, Sendable {
    let kind: BrowserNavigationFailureKind
    let phase: BrowserNavigationFailurePhase
    let failingURL: URL?
    let errorDomain: String
    let errorCode: Int
}

enum BrowserNavigationFailureKind: Equatable, Sendable {
    case offline
    case timedOut
    case cannotFindServer
    case cannotConnect
    case connectionLost
    case secureConnectionFailed
    case tooManyRedirects
    case unsupportedAddress
    case blocked
    case unavailable
    case webContentProcessStopped
    case unknown
}

enum BrowserNavigationFailurePhase: Equatable, Sendable {
    case provisional
    case committed
}
