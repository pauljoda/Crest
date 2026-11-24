import AppKit

extension BrowserChromeState {
    // MARK: - Actions - Copying

    /// Puts `text` on the pasteboard and says so in the window's notice.
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showNotice(.copied)
    }
}
