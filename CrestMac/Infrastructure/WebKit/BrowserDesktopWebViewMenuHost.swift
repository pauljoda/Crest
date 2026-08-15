import Foundation

/// What Crest contributes to WebKit's own web-content context menu.
///
/// AppKit builds and tears the menu down on the main thread while the
/// right-click is still being handled, so every answer here is synchronous.
@MainActor
protocol BrowserDesktopWebViewMenuHost: AnyObject {
    /// The link the right-click that is opening this menu landed on, when
    /// "Open Link in Split View" applies to it.
    ///
    /// Consumes the capture: nil means "no link, or nowhere to put one", and
    /// the same report is never handed to a second menu.
    func takeSplitViewLinkDestination() -> URL?

    /// Opens `url` as a new card beside the tab this page presents.
    func openLinkInSplitView(_ url: URL)

    /// Drops a capture the closing menu never used.
    func discardSplitViewLinkCapture()
}
