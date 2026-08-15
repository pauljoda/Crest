/// Settings destinations whose implementations are available in the macOS shell.
enum BrowserPlatformSettingsDestinationCatalog {
    static let cases = BrowserSettingsDestination.allCases

    static func isAvailable(
        _ destination: BrowserSettingsDestination
    ) -> Bool {
        true
    }
}
