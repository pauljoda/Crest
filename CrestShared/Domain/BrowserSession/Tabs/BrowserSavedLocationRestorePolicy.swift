import Foundation

enum BrowserSavedLocationRestorePolicy {
    /// Whether returning `tab` to its saved address would change anything: the
    /// core says the tab is away, or its page is on the way somewhere else.
    ///
    /// TRANSITIONAL until the core's `Pages` holds each page's pending
    /// address: `pendingURL` is live page state the core does not see yet, so
    /// that one comparison stays here.
    static func shouldRestore(_ tab: BrowserTab, pendingURL: URL?) -> Bool {
        guard let root = tab.savedSiteURL, tab.supportsSavedLocationEditing else { return false }
        if tab.isAwayFromSavedLocation { return true }
        guard let pendingURL else { return false }
        return (BrowserHistoryURL.normalized(pendingURL) ?? pendingURL)
            != (BrowserHistoryURL.normalized(root) ?? root)
    }
}
