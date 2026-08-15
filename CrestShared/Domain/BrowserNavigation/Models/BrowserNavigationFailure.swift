import Foundation

struct BrowserNavigationFailure: Equatable, Sendable {
    let kind: BrowserNavigationFailureKind
    let phase: BrowserNavigationFailurePhase
    let failingURL: URL?
    let errorDomain: String
    let errorCode: Int
}
