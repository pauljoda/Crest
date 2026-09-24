/// Settings destinations whose implementations are available in the mobile shell.
enum BrowserPlatformSettingsDestinationCatalog {
    static let cases = BrowserSettingsDestination.all.filter(isAvailable)

    static func isAvailable(
        _ destination: BrowserSettingsDestination
    ) -> Bool {
        // WebKit's private feature registry and the rebindable keyboard
        // command table are macOS surfaces.
        destination != .featureFlags
            && destination != .shortcuts
    }
}
