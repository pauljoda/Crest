import Foundation

enum BrowserSavedLocationRestorePolicy {
    static func shouldRestore(_ tab: BrowserTab, pendingURL: URL?) -> Bool {
        guard let root = tab.savedSiteURL, tab.supportsSavedLocationEditing else { return false }
        if tab.isAwayFromSavedLocation { return true }
        guard let pendingURL else { return false }
        return (BrowserHistoryURL.normalized(pendingURL) ?? pendingURL)
            != (BrowserHistoryURL.normalized(root) ?? root)
    }
}
