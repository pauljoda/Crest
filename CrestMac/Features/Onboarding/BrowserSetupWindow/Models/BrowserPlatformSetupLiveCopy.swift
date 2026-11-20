import SwiftUI

/// One opening of setup's live copy on the Mac: its window and what the
/// window runs on.
@MainActor
struct BrowserPlatformSetupLiveCopy: Identifiable {
    // MARK: - Variables

    let id = UUID()
    let store: BrowserStore
    let pages: BrowserPagePool
    let chrome = BrowserChromeState(sidebarIsPresented: true)
    let transientBrowsing = BrowserTransientBrowsingCoordinator()

    // MARK: - Initializers

    /// A copy over `store`, whose pages keep no website data.
    init(store: BrowserStore) {
        self.store = store
        pages = BrowserPagePool(browser: store, usesEphemeralWebsiteDataStores: true)
    }
}
