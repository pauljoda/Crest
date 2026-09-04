import AppKit
import SwiftUI
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserSplitPanelViewportTests: XCTestCase {
    func testOpeningAndResizingPanelUpdatesTheResidentPageViewport() async throws {
        let space = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        let page = BrowserPage(
            configuration: BrowserPageConfiguration.make(for: space.profile, websiteDataStore: .nonPersistent()),
            dialogPresenter: BrowserDialogPresenter(), downloadCenter: BrowserDownloadCenter(),
            permissionCenter: BrowserSitePermissionCenter(), spaceID: space.id, profileID: space.profile.id,
            spaceName: space.name, openNewTab: { _ in }
        )
        let panelView = WKWebView()
        let state = ViewportState()
        let hosting = NSHostingView(rootView: ViewportSurface(state: state, tab: tab, page: page, panel: panelView))
        let window = NSWindow(
            contentRect: CGRect(x: 30, y: 30, width: 1000, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer {
            page.webView.stopLoading()
            panelView.stopLoading()
            window.close()
        }
        page.webView.loadHTMLString(
            "<!doctype html><meta name='viewport' content='width=device-width'><body>Responsive page</body>",
            baseURL: nil)
        let seam = BrowserChromeLayout.pageBrandSeamWidth * 2
        try await assertViewport(page.webView, width: 1000 - seam, hosting: hosting)

        state.panelWidth = 360
        try await assertViewport(page.webView, width: 632 - seam, hosting: hosting)
        XCTAssertEqual(panelView.frame.width, 360 - seam, accuracy: 1)
        XCTAssertEqual(page.webView.pageZoom, 1)

        state.panelWidth = 500
        try await assertViewport(page.webView, width: 492 - seam, hosting: hosting)
        XCTAssertEqual(panelView.frame.width, 500 - seam, accuracy: 1)

        state.panelWidth = nil
        try await assertViewport(page.webView, width: 1000 - seam, hosting: hosting)
        XCTAssertEqual(page.webView.pageZoom, 1)

        page.webView.loadHTMLString(
            "<!doctype html><body style='min-width:1249px'>Fixed-width page</body>", baseURL: nil)
        state.panelWidth = 360
        let fittedZoom = (632 - seam) / 1249
        for _ in 0..<100 {
            hosting.layoutSubtreeIfNeeded()
            if abs(page.webView.pageZoom - fittedZoom) < 0.001 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(page.webView.pageZoom, fittedZoom, accuracy: 0.001)
        XCTAssertEqual(page.pageZoom, 1, "Fitting must not overwrite the person's requested zoom.")
        state.panelWidth = nil
        try await assertViewport(page.webView, width: 1000 - seam, hosting: hosting)
        XCTAssertEqual(page.webView.pageZoom, 1)
    }

    func testFittingOnlyReducesZoomWhenAnAuthoredMinimumExceedsTheCard() {
        XCTAssertEqual(
            BrowserPageViewportFitPolicy.zoom(requested: 1, viewportWidth: 1000, minimumContentWidth: 1249),
            1000 / 1249, accuracy: 0.0001)
        XCTAssertEqual(
            BrowserPageViewportFitPolicy.zoom(requested: 1.25, viewportWidth: 1000, minimumContentWidth: 600), 1.25)
        XCTAssertEqual(
            BrowserPageViewportFitPolicy.zoom(requested: 0.67, viewportWidth: 1000, minimumContentWidth: 1249), 0.67)
        XCTAssertEqual(BrowserPageViewportFitPolicy.zoom(requested: 1, viewportWidth: 1000, minimumContentWidth: 0), 1)
        XCTAssertEqual(
            BrowserPageViewportFitPolicy.zoom(requested: 1, viewportWidth: .nan, minimumContentWidth: 1249), 1)
    }

    private func assertViewport(_ webView: WKWebView, width: CGFloat, hosting: NSView) async throws {
        var viewport: Double?
        for _ in 0..<100 {
            hosting.layoutSubtreeIfNeeded()
            viewport = (try? await webView.evaluateJavaScript("window.innerWidth")) as? Double
            if abs(webView.frame.width - width) < 1, let viewport, abs(viewport - width) < 1 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(webView.frame.width, width, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(viewport), Double(width), accuracy: 1)
    }

    @Observable
    final class ViewportState { var panelWidth: CGFloat? }

    private struct ViewportSurface: View {
        let state: ViewportState
        let tab: BrowserTab
        let page: BrowserPage
        let panel: WKWebView

        var body: some View {
            BrowserSplitColumnsView(
                members: [tab], focusedTabID: tab.id, frameInsets: EdgeInsets(), accent: .blue,
                placeholderIndex: nil, liftedTabID: nil,
                widthTransaction: .constant(.init(persistedFractions: [1])), onResizeCommit: { _ in },
                onFocus: { _ in }, usesTransparentInnerSurface: { _ in false },
                content: { _, _ in
                    BrowserPlatformWebView(page: page, isPageActive: true, focusRestorationGate: .suppressed)
                        .modifier(
                            BrowserExtensionSidebarPageFitModifier(page: page, isEnabled: state.panelWidth != nil))
                },
                panel: state.panelWidth.map { .init(requestedWidth: $0) }, onPanelResizeCommit: { _ in },
                panelContent: { BrowserExtensionSidebarWebView(webView: panel, userInteracted: {}) }
            )
            .transaction { $0.disablesAnimations = true }
        }
    }
}
