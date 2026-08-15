enum BrowserSystemPasswordWriteThroughAvailability: Equatable, Sendable {
    case available
    case unsupportedPlatform
    case isolatedLaunch
    case systemVersionRequired
    case managedBrowserCapabilityRequired
}
