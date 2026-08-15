/// Settings destinations whose implementations are available in the mobile shell.
enum BrowserPlatformSettingsDestinationCatalog {
    static let cases = BrowserSettingsDestination.allCases.filter(isAvailable)

    static func isAvailable(
        _ destination: BrowserSettingsDestination
    ) -> Bool {
        // Extensions are a macOS-only feature, and keyboard shortcuts have no
        // mobile surface to bind.
        destination != .extensions && destination != .shortcuts
    }
}
