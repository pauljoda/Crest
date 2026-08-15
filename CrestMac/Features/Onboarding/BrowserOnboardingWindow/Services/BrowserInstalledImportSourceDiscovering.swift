@MainActor
protocol BrowserInstalledImportSourceDiscovering {
    func installedSources() -> [BrowserInstalledImportSource]
}
