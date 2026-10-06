@MainActor
struct LiveBrowserInstalledImportSourceDiscovery:
    BrowserInstalledImportSourceDiscovering
{
    func installedSources() -> [BrowserInstalledImportSource] {
        BrowserInstalledImportSourceDetector.installedSources()
    }

    func unlistedSources() -> [BrowserInstalledImportSource] {
        BrowserInstalledImportSourceDetector.unlistedSources()
    }
}
