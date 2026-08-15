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
