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
    var blockedPopupNotice: BrowserBlockedPopupNotice? { get }
    /// Whether the page can go on the Home Screen: a web page outside private
    /// browsing, whose title, icon and address the Home Screen would keep.
    var canAddToHomeScreen: Bool { get }

    func goBack()
    func goForward()
    func goBack(to item: BrowserNavigationHistoryItem)
    func goForward(to item: BrowserNavigationHistoryItem)
    func reloadOrStop()
    func reload()
    func stopLoading()
    func reloadFromOrigin()
    /// Clears what the page's site keeps in `category` in its Space, reloads
    /// the page, and says how it went.
    func clearSiteData(_ category: BrowsingDataCategory) async
    func togglePreferredContentMode()
    func toggleReaderMode()
    func presentFind()
    func zoomIn()
    func zoomOut()
    func resetZoom()
    func allowAutomaticPopupsForBlockedSite()
    @discardableResult func copyPageLink() -> Bool
    @discardableResult func copyPageLinkAsMarkdown() -> Bool
    func printPage()
    /// Opens Apple's Add to Home Screen for the page, pointing on iPad at
    /// `source`, the control that asked, a frame in the window.
    func addToHomeScreen(from source: CGRect?)
    func exportPDF(to destination: MobileBrowserFileExportDestination)
    func exportWebArchive(to destination: MobileBrowserFileExportDestination)
    /// Brings every resident page in line with its Space's content blocking.
    func reconcileContentBlocking() async
    /// Puts the content rules the core converted last in force on every
    /// resident page.
    func reloadContentBlocking() async
}
