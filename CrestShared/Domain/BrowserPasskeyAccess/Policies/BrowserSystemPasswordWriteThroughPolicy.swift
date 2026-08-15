enum BrowserSystemPasswordWriteThroughPolicy {
    static func availability(
        isMobilePlatform: Bool,
        supportsSystemAPI: Bool,
        hasManagedBrowserCapability: Bool,
        isLaunchIsolated: Bool
    ) -> BrowserSystemPasswordWriteThroughAvailability {
        guard isMobilePlatform else { return .unsupportedPlatform }
        guard !isLaunchIsolated else { return .isolatedLaunch }
        guard supportsSystemAPI else { return .systemVersionRequired }
        guard hasManagedBrowserCapability else {
            return .managedBrowserCapabilityRequired
        }
        return .available
    }

    static func shouldOffer(
        preferences: BrowserCredentialPreferences,
        availability: BrowserSystemPasswordWriteThroughAvailability,
        isPrivateBrowsing: Bool
    ) -> Bool {
        preferences.alsoOffersSaveToSystemPasswords
            && availability == .available
            && !isPrivateBrowsing
    }
}
