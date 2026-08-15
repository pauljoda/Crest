import Observation
import SwiftUI

@Observable
@MainActor
final class MobileBrowserRootModel {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let spaceAccess: BrowserSpaceAccessController
    let windowState: BrowserWindowStateStore?
    let startupBehavior: BrowserStartupBehavior

    var address = ""
    var hasPreparedBrowser = false
    var sidebarWidthTransaction: BrowserSidebarWidthTransaction
    /// Live column fractions for the presented split, seeded from this window's
    /// stored layout whenever membership changes. Pointer-rate resizing lives in
    /// the transaction so a divider drag is not a persistence event per frame.
    var splitWidthTransaction = BrowserSplitWidthTransaction(
        persistedFractions: []
    )

    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        navigation: MobileBrowserNavigationState,
        spaceAccess: BrowserSpaceAccessController,
        windowState: BrowserWindowStateStore?,
        startupBehavior: BrowserStartupBehavior,
        persistedSidebarWidth: CGFloat
    ) {
        self.browser = browser
        self.pages = pages
        self.navigation = navigation
        self.spaceAccess = spaceAccess
        self.windowState = windowState
        self.startupBehavior = startupBehavior
        sidebarWidthTransaction = BrowserSidebarWidthTransaction(
            persistedWidth: persistedSidebarWidth
        )
    }
}
