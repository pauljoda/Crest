enum BrowserSystemPasswordWriteThroughAvailability: Equatable, Sendable {
    case available
    case unsupportedPlatform
    case isolatedLaunch
    case systemVersionRequired
    case managedBrowserCapabilityRequired
}

enum BrowserSystemPasswordWriteThroughError: Error, Equatable {
    case unavailable
    case invalidScope
    case missingPresentationAnchor
}
