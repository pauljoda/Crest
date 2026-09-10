import AppKit

@MainActor
enum BrowserPageLinkClipboard {
    @discardableResult
    static func copy(_ url: URL?) -> Bool {
        guard let url else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(url.absoluteString, forType: .string)
    }
}
