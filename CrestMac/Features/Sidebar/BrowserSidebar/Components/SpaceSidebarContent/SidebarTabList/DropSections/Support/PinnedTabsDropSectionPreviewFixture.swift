import Foundation

@MainActor
struct PinnedTabsDropSectionPreviewFixture {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let space: BrowserSpace
    let spaceAccess: BrowserSpaceAccessController

    init() {
        let sidebar = BrowserSidebarInteractionPreviewFixture()
        let previewSpace = sidebar.spaceWithoutPinnedTabs
        let browser = sidebar.browser
        if let spaceIndex = browser.session.spaces.firstIndex(where: {
            $0.id == previewSpace.id
        }) {
            browser.session.spaces[spaceIndex] = previewSpace
        }
        self.browser = browser
        space = previewSpace
        spaceAccess = sidebar.spaceAccess
        pages = BrowserPagePool(
            monitorsMemoryPressure: false,
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true,
            extensionControllerPool: BrowserExtensionControllerPool(
                packageStore: PinnedTabsDropSectionPreviewExtensionPackageStore(),
                registry: BrowserExtensionRegistry(
                    persistence: InMemoryBrowserExtensionRegistryPersistence()
                ),
                usesEphemeralWebKitStorage: true
            ),
            chromeWebStoreProvider: BrowserChromeWebStoreProvider(
                download: { _ in
                    throw BrowserChromeWebStoreProviderError.invalidResponse
                }
            ),
            permissionCenter: BrowserSitePermissionCenter(
                persistence: InMemoryBrowserSitePermissionPersistence()
            ),
            websiteDataStoreRemover:
                PinnedTabsDropSectionPreviewWebsiteDataStoreRemover(),
            contentRuleListProvider: BrowserContentRuleListProvider(
                ruleListStore: nil
            )
        )
    }
}
