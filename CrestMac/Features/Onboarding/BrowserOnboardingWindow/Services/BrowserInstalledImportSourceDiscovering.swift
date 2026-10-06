@MainActor
protocol BrowserInstalledImportSourceDiscovering {
    func installedSources() -> [BrowserInstalledImportSource]

    /// The other browsers built on Chromium installed here, found by looking
    /// for their data, which setup offers when the person's browser is not
    /// listed.
    func unlistedSources() -> [BrowserInstalledImportSource]
}

extension BrowserInstalledImportSourceDiscovering {
    func unlistedSources() -> [BrowserInstalledImportSource] { [] }
}
