import AppKit
import Foundation

/// What Crest contributes to WebKit's own web-content context menu. AppKit
/// builds and tears the menu down on the main thread while the right-click is
/// still being handled, so every answer here is synchronous.
extension BrowserPage {
    /// Whether a link the engine opens in a new tab or window from this page
    /// becomes a tab of the page's Space: the page is a tab's.
    var opensLinksInCurrentSpace: Bool { navigationContext != nil }

    /// The content the right-click that is opening this menu landed on.
    /// Consumes the capture: nil means no fresh page report arrived, and the
    /// same report is never handed to a second menu. The shared page action
    /// builder decides which captured link and selection actions are available.
    func takeMenuContext() -> BrowserDesktopWebViewMenuContext? {
        guard let captured = linkContextCapture.take() else { return nil }
        return BrowserDesktopWebViewMenuContext(
            linkURL: captured.linkURL, imageDownloadURL: captured.imageURL,
            selectionText: captured.selectionText, isEditable: captured.isEditable)
    }

    func downloadImage(from url: URL) {
        let request = URLRequest(url: url)
        Task { @MainActor [weak self] in
            guard let self, let webView = webKitView else { return }
            let download = await webView.startDownload(using: request)
            guard !Task.isCancelled else {
                _ = await download.cancel()
                return
            }
            startDownload(download, in: webView, isUserInitiated: true)
        }
    }

    func discardSplitViewLinkCapture() {
        linkContextCapture.clear()
    }
}
