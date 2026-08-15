@MainActor
struct LiveBrowserInstalledImportSourceDiscovery:
    BrowserInstalledImportSourceDiscovering
{
    func installedSources() -> [BrowserInstalledImportSource] {
        BrowserInstalledImportSourceDetector.installedSources()
    }
}
