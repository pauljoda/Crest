import AppKit

/// The pasteboard as the place a page's address goes. It takes only links
/// the core made, so everything it copies has been through Super Copy.
@MainActor
enum BrowserPageLinkClipboard {
    @discardableResult
    static func copy(_ links: [BrowserCopiedLink]) -> Bool {
        guard !links.isEmpty else { return false }
        return write(links.map(\.url.absoluteString).joined(separator: "\n"))
    }

    @discardableResult
    static func copy(_ link: BrowserCopiedLink?) -> Bool {
        guard let link else { return false }
        return write(link.url.absoluteString)
    }

    /// Copies `link` as Markdown, labelled `title`.
    @discardableResult
    static func copyMarkdown(_ link: BrowserCopiedLink?, title: String) -> Bool {
        guard let link else { return false }
        return write(link.markdown(title: title))
    }

    private static func write(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
