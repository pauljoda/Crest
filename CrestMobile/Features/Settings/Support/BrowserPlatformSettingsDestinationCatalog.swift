/// Settings destinations whose implementations are available in the mobile shell.
enum BrowserPlatformSettingsDestinationCatalog {
    static let cases = BrowserSettingsDestination.allCases.filter(isAvailable)

    static func isAvailable(
        _ destination: BrowserSettingsDestination
    ) -> Bool {
        // Extensions and WebKit's private feature registry are macOS-only
        // surfaces, and keyboard shortcuts have no mobile command table to bind.
        destination != .extensions
            && destination != .featureFlags
            && destination != .shortcuts
    }
}
