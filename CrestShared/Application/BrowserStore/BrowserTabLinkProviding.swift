import Foundation

/// Resolves a tab's address without selecting it or creating a page.
@MainActor
protocol BrowserTabLinkProviding: AnyObject {
    func linkURL(for tab: BrowserTab, in space: BrowserSpace) -> URL?
}
