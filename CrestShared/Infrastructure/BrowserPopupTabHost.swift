import Foundation
import WebKit

/// Tab-level operations a page pool needs to host adopted popups. Both are
/// synchronous because WebKit demands the popup's web view before it returns.
@MainActor
struct BrowserPopupTabHost {
    var openTab: (URL?, SpaceID) -> BrowserPopupTabRegistration?
    var closeTab: (TabID, SpaceID) -> Void

    init(
        openTab: @escaping (URL?, SpaceID) -> BrowserPopupTabRegistration?,
        closeTab: @escaping (TabID, SpaceID) -> Void
    ) {
        self.openTab = openTab
        self.closeTab = closeTab
    }

    /// Declines every popup. Pools built without a tab host (tests, previews)
    /// fall back to the URL-routed path instead of adopting.
    static let unavailable = BrowserPopupTabHost(
        openTab: { _, _ in nil },
        closeTab: { _, _ in }
    )
}
