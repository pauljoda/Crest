import UIKit

/// The pasteboard as the place a page's address goes. It takes only links
/// the core made, so everything it copies has been through Super Copy.
@MainActor
enum BrowserPageLinkClipboard {
    @discardableResult
    static func copy(_ links: [BrowserCopiedLink]) -> Bool {
        guard !links.isEmpty else { return false }
        UIPasteboard.general.string = links.map(\.url.absoluteString).joined(separator: "\n")
        return true
    }

    @discardableResult
    static func copy(_ link: BrowserCopiedLink?) -> Bool {
        guard let link else { return false }
        UIPasteboard.general.url = link.url
        return true
    }

    /// Copies `link` as Markdown, labelled `title`.
    @discardableResult
    static func copyMarkdown(_ link: BrowserCopiedLink?, title: String) -> Bool {
        guard let link else { return false }
        UIPasteboard.general.string = link.markdown(title: title)
        return true
    }
}
