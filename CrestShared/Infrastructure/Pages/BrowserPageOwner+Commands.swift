import Foundation

// MARK: - Page commands

extension BrowserPageOwner {
    var canGoBack: Bool { activePage?.live.canGoBack == true }
    var canGoForward: Bool { activePage?.live.canGoForward == true }
    var backHistory: [BrowserNavigationHistoryItem] { activePage?.backHistory ?? [] }
    var forwardHistory: [BrowserNavigationHistoryItem] { activePage?.forwardHistory ?? [] }

    var pageZoomLabel: String {
        (activePage?.pageZoom ?? 1).pageZoomPercentage
    }

    var readerModeState: BrowserReaderModeState {
        activePage?.readerModeState ?? .unavailable
    }

    var readerModeActionTitle: LocalizedStringResource {
        readerModeState.actionTitle
    }

    func goBack() { activePage?.goBack() }
    func goForward() { activePage?.goForward() }
    func goBack(to item: BrowserNavigationHistoryItem) { activePage?.goBack(toDepth: item.depth) }
    func goForward(to item: BrowserNavigationHistoryItem) { activePage?.goForward(toDepth: item.depth) }

    func stopLoading() {
        activePage?.stopLoading()
    }

    func clearSiteDataAndReload() async {
        await activePage?.clearSiteDataAndReload()
    }

    func presentFind() {
        activePage?.presentFind()
    }

    func toggleReaderMode() {
        activePage?.toggleReaderMode()
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        activePage?.copyPageLinkAsMarkdown() == true
    }

    func printPage() {
        activePage?.printPage()
    }

    /// Gives every page the host keeps the new default zoom.
    func defaultPageZoomDidChange(to zoom: CGFloat) {
        host.defaultPageZoomDidChange(to: zoom)
    }
}
