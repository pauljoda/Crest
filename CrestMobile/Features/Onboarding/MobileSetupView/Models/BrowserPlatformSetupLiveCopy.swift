import SwiftUI

/// One opening of setup's live copy on iPhone and iPad: its browser and what
/// the browser runs on.
@MainActor
struct BrowserPlatformSetupLiveCopy: Identifiable {
    // MARK: - Variables

    let id = UUID()
    let store: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation = MobileBrowserNavigationState(
        regularSidebarIsPresented: true, initiallyShowsCompactPage: false, allowsCompactFloatingSidebar: false)
    let transientBrowsing = BrowserTransientBrowsingCoordinator()

    // MARK: - Initializers

    /// A copy over `store`, whose pages keep no website data.
    init(store: BrowserStore) {
        self.store = store
        pages = MobileBrowserPageStore(browser: store, usesEphemeralWebsiteDataStores: true)
        store.tabLinkProvider = pages
        store.tabCopying = pages
    }
}
