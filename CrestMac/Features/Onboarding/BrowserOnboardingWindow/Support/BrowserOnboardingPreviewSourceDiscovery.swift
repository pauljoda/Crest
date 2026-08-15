@MainActor
struct BrowserOnboardingPreviewSourceDiscovery:
    BrowserInstalledImportSourceDiscovering
{
    let sources: [BrowserInstalledImportSource]

    func installedSources() -> [BrowserInstalledImportSource] {
        sources
    }
}
