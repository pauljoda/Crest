import Foundation

@MainActor
struct MobilePageActionsPreviewStub: MobilePageActions {
    let assignment: BrowserTabRuntimeAssignment

    var isAvailable: Bool { true }
    var pageAssignment: BrowserTabRuntimeAssignment? { assignment }
    var activePage: MobileBrowserPage? { nil }
    var activeURL: URL? { URL(filePath: "/CrestPreview/page.html") }
    var canGoBack: Bool { true }
    var canGoForward: Bool { true }
    var backHistory: [BrowserNavigationHistoryItem] {
        [
            BrowserNavigationHistoryItem(
                depth: -1,
                title: "Earlier Page",
                url: URL(filePath: "/CrestPreview/earlier.html")
            )
        ]
    }
    var forwardHistory: [BrowserNavigationHistoryItem] {
        [
            BrowserNavigationHistoryItem(
                depth: 1,
                title: "Later Page",
                url: URL(filePath: "/CrestPreview/later.html")
            )
        ]
    }
    var preferredContentModeActionTitle: LocalizedStringResource {
        "Request Desktop Website"
    }
    var readerModeActionTitle: LocalizedStringResource { "Show Reader" }
    var readerModeState: BrowserReaderModeState { .available }
    var pageZoomLabel: String { "100%" }

    func goBack() {}
    func goForward() {}
    func goBack(to _: BrowserNavigationHistoryItem) {}
    func goForward(to _: BrowserNavigationHistoryItem) {}
    func reloadOrStop() {}
    func reload() {}
    func stopLoading() {}
    func reloadFromOrigin() {}
    func clearSiteDataAndReload() async {}
    func togglePreferredContentMode() {}
    func toggleReaderMode() {}
    func presentFind() {}
    func zoomIn() {}
    func zoomOut() {}
    func resetZoom() {}
    func copyPageLink() -> Bool { true }
    func copyPageLinkAsMarkdown() -> Bool { true }
    func printPage() {}
    func exportPDF(to _: MobileBrowserFileExportDestination) {}
    func exportWebArchive(to _: MobileBrowserFileExportDestination) {}
    func reconcileContentBlocking(in _: BrowserSession) async {}
}
