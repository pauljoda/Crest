import Foundation

@MainActor
protocol MobilePageActions {
    var isAvailable: Bool { get }
    var pageAssignment: BrowserTabRuntimeAssignment? { get }
    var activePage: MobileBrowserPage? { get }
    var activeURL: URL? { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    var backHistory: [BrowserNavigationHistoryItem] { get }
    var forwardHistory: [BrowserNavigationHistoryItem] { get }
    var preferredContentModeActionTitle: LocalizedStringResource { get }
    var readerModeActionTitle: LocalizedStringResource { get }
    var readerModeState: BrowserReaderModeState { get }
    var pageZoomLabel: String { get }

    func goBack()
    func goForward()
    func goBack(to item: BrowserNavigationHistoryItem)
    func goForward(to item: BrowserNavigationHistoryItem)
    func reloadOrStop()
    func reload()
    func stopLoading()
    func reloadFromOrigin()
    func clearSiteDataAndReload() async
    func togglePreferredContentMode()
    func toggleReaderMode()
    func presentFind()
    func zoomIn()
    func zoomOut()
    func resetZoom()
    @discardableResult func copyPageLink() -> Bool
    @discardableResult func copyPageLinkAsMarkdown() -> Bool
    func printPage()
    func exportPDF(to destination: MobileBrowserFileExportDestination)
    func exportWebArchive(to destination: MobileBrowserFileExportDestination)
    func reconcileContentBlocking(in session: BrowserSession) async
}
