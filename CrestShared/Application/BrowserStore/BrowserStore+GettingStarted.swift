import Foundation

extension BrowserStore {
    /// Closing a saved native view dismisses its presentation, retaining the
    /// document in Saved. Current copies continue through the normal close path.
    func dismissNativeTab(_ id: TabID, matching assignment: BrowserSpaceRuntimeAssignment) {
        guard let space = selectedSpace, BrowserSpaceRuntimeAssignment(space: space) == assignment,
            space.selectedTabID == id,
            space.tabs.first(where: { $0.id == id })?.nativeContent != nil
        else { return }
        selectDismissalFallback(afterDismissing: id)
    }

    @discardableResult
    func openGettingStarted() -> TabID? {
        if let existing = selectedSpace?.tabs.first(where: {
            $0.nativeContent == .gettingStarted
        }) {
            selectTab(existing.id)
            return existing.id
        }
        return openNativeTab(.gettingStarted, title: String(localized: "Getting Started"), symbol: "book.closed.fill")
    }

    /// Native documents enter the same session mutation and persistence path as
    /// websites. No page pool or second selection model is owned by the document.
    @discardableResult
    func openNativeTab(_ content: BrowserNativeTabContent, title: String, symbol: String) -> TabID? {
        guard let space = selectedSpace else { return nil }
        let id = session.openTab(
            title: title, url: nil, nativeContent: content, symbol: symbol,
            in: space.id, placement: .saved)
        persist(scope: .core)
        return id
    }
}
