import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserRootModel {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let spaceAccess: BrowserSpaceAccessController
    let windowState: BrowserWindowStateStore?
    let startupBehavior: BrowserStartupBehavior

    var address = ""
    var isAddressEditing = false
    var hasRestoredExtensions = false
    var isURLCopiedFeedbackVisible = false
    var visiblePageZoomFeedbackLabel: String?
    var isFloatingSidebarPresented = false
    var isWindowFocused = true
    var sidebarWidthTransaction: BrowserSidebarWidthTransaction
    /// Pointer-rate column widths for the presented split, seeded from this
    /// window's stored layout and committed back to it once per drag. A window
    /// presenting a single tab holds the one-column identity rather than a
    /// separate "no split" state.
    var splitWidthTransaction = BrowserSplitWidthTransaction(
        persistedFractions: [1]
    )
    /// The card this window is carrying on the pointer, if any.
    ///
    /// Per window rather than per surface, because the shell has to reach it
    /// too: the preview travels in a window ordered above this one, and that is
    /// seated at the root rather than inside the content area it left.
    let splitCardLift = BrowserSplitCardLiftState()

    init(
        browser: BrowserStore,
        pages: BrowserPagePool,
        chrome: BrowserChromeState,
        spaceAccess: BrowserSpaceAccessController,
        windowState: BrowserWindowStateStore?,
        startupBehavior: BrowserStartupBehavior,
        persistedSidebarWidth: CGFloat
    ) {
        self.browser = browser
        self.pages = pages
        self.chrome = chrome
        self.spaceAccess = spaceAccess
        self.windowState = windowState
        self.startupBehavior = startupBehavior
        sidebarWidthTransaction = BrowserSidebarWidthTransaction(
            persistedWidth: persistedSidebarWidth
        )
    }
}
