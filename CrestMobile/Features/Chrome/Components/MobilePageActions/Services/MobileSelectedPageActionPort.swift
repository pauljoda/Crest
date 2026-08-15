import Foundation

@MainActor
struct MobileSelectedPageActionPort: MobilePageActions {
    private let browser: BrowserStore
    private let pages: MobileBrowserPageStore
    private let expectedAssignment: BrowserTabRuntimeAssignment

    init?(
        browser: BrowserStore,
        pages: MobileBrowserPageStore
    ) {
        guard let tab = browser.selectedTab,
            let space = browser.selectedSpace
        else { return nil }
        self.init(
            browser: browser,
            pages: pages,
            expectedAssignment: BrowserTabRuntimeAssignment(
                tabID: tab.id,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
    }

    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        expectedAssignment: BrowserTabRuntimeAssignment
    ) {
        self.browser = browser
        self.pages = pages
        self.expectedAssignment = expectedAssignment
    }

    var isAvailable: Bool {
        activePage != nil
    }

    var pageAssignment: BrowserTabRuntimeAssignment? {
        isAvailable ? expectedAssignment : nil
    }

    var activePage: MobileBrowserPage? {
        guard let tab = browser.selectedTab,
            let space = browser.selectedSpace,
            tab.id == expectedAssignment.tabID,
            space.id == expectedAssignment.spaceID,
            space.profile.id == expectedAssignment.profileID,
            let page = pages.activePage,
            page.tabID == expectedAssignment.tabID,
            page.spaceID == expectedAssignment.spaceID,
            page.profileID == expectedAssignment.profileID
        else { return nil }
        return page
    }

    var activeURL: URL? {
        activePage?.url
    }

    var canGoBack: Bool {
        activePage?.canGoBack == true
    }

    var canGoForward: Bool {
        activePage?.canGoForward == true
    }

    var backHistory: [BrowserNavigationHistoryItem] {
        activePage?.backHistory ?? []
    }

    var forwardHistory: [BrowserNavigationHistoryItem] {
        activePage?.forwardHistory ?? []
    }

    var preferredContentModeActionTitle: LocalizedStringResource {
        activePage?.isRequestingDesktopSite == true
            ? "Request Mobile Website"
            : "Request Desktop Website"
    }

    var readerModeActionTitle: LocalizedStringResource {
        readerModeState.isActive ? "Hide Reader" : "Show Reader"
    }

    var readerModeState: BrowserReaderModeState {
        activePage?.readerModeState ?? .unavailable
    }

    var pageZoomLabel: String {
        BrowserPageZoomPolicy.percentageLabel(for: activePage?.pageZoom ?? 1)
    }

    func goBack() {
        activePage?.goBack()
    }

    func goForward() {
        activePage?.goForward()
    }

    func goBack(to item: BrowserNavigationHistoryItem) {
        activePage?.goBack(toDepth: item.depth)
    }

    func goForward(to item: BrowserNavigationHistoryItem) {
        activePage?.goForward(toDepth: item.depth)
    }

    func reloadOrStop() {
        activePage?.reloadOrStop()
    }

    func reload() {
        activePage?.reload()
    }

    func stopLoading() {
        activePage?.stopLoading()
    }

    func reloadFromOrigin() {
        activePage?.performReload(.fromOrigin)
    }

    func clearSiteDataAndReload() async {
        await activePage?.clearSiteDataAndReload()
    }

    func togglePreferredContentMode() {
        activePage?.togglePreferredContentMode()
    }

    func toggleReaderMode() {
        activePage?.toggleReaderMode()
    }

    func presentFind() {
        activePage?.presentFind()
    }

    func zoomIn() {
        guard activePage != nil else { return }
        pages.zoomIn()
    }

    func zoomOut() {
        guard activePage != nil else { return }
        pages.zoomOut()
    }

    func resetZoom() {
        guard activePage != nil else { return }
        pages.resetZoom()
    }

    @discardableResult
    func copyPageLink() -> Bool {
        guard isAvailable else { return false }
        return pages.copyPageLink()
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        guard isAvailable else { return false }
        return pages.copyPageLinkAsMarkdown()
    }

    func printPage() {
        activePage?.printPage()
    }

    func exportPDF(to destination: MobileBrowserFileExportDestination) {
        activePage?.exportPDF(to: destination)
    }

    func exportWebArchive(to destination: MobileBrowserFileExportDestination) {
        activePage?.exportWebArchive(to: destination)
    }

    func reconcileContentBlocking(in session: BrowserSession) async {
        await pages.reconcileContentBlocking(in: session)
    }
}
