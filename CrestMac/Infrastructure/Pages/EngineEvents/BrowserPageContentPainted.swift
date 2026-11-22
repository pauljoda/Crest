import Foundation

/// The page's document painted content of its own for the first time.
struct BrowserPageContentPainted: BrowserPageEngineEvent {
    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.hasPaintedContent = true
    }
}
