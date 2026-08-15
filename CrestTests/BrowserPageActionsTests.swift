import XCTest
@testable import Crest

final class BrowserPageZoomPolicyTests: XCTestCase {
    func testDeveloperModeAutomaticallyRecognizesLocalPagesAndHostnames() {
        let localURLs = [
            "http://localhost:3000/dashboard",
            "https://api.preview.localhost:8443",
            "http://devbox:8080",
            "https://preview.local",
            "https://project.test",
            "https://service.internal",
            "http://router.home.arpa",
            "http://dashboard.lan",
            "file:///tmp/crest-preview/index.html",
        ]

        for value in localURLs {
            XCTAssertTrue(
                BrowserDeveloperModePolicy.isAutomatic(for: URL(string: value)),
                value
            )
        }
    }

    func testDeveloperModeAutomaticallyRecognizesLocalIPv4Addresses() {
        let localURLs = [
            "http://127.0.0.1:1",
            "http://127.42.99.4",
            "http://0.0.0.0:3000",
            "http://10.23.45.67",
            "http://172.16.0.1",
            "http://172.31.255.255",
            "http://192.168.0.25",
            "http://169.254.1.1",
        ]

        for value in localURLs {
            XCTAssertTrue(
                BrowserDeveloperModePolicy.isAutomatic(for: URL(string: value)),
                value
            )
        }
    }

    func testDeveloperModeAutomaticallyRecognizesLocalIPv6Addresses() {
        let localURLs = [
            "http://[::1]:3000",
            "http://[::]:3000",
            "http://[fd12:3456:789a::1]",
            "http://[fe80::1]",
            "http://[::ffff:127.0.0.1]",
            "http://[::ffff:192.168.1.20]",
        ]

        for value in localURLs {
            XCTAssertTrue(
                BrowserDeveloperModePolicy.isAutomatic(for: URL(string: value)),
                value
            )
        }
    }

    func testDeveloperModeRejectsPublicAndLocalLookalikeDestinations() {
        let publicURLs = [
            "https://localhost.example.com",
            "https://project.test.example.com",
            "http://128.0.0.1",
            "http://172.15.255.255",
            "http://172.32.0.1",
            "http://192.167.255.255",
            "http://169.253.255.255",
            "http://8.8.8.8",
            "http://[2001:4860:4860::8888]",
            "https://example.com",
            "data:text/plain,Hello",
        ]

        for value in publicURLs {
            XCTAssertFalse(
                BrowserDeveloperModePolicy.isAutomatic(for: URL(string: value)),
                value
            )
        }
        XCTAssertFalse(BrowserDeveloperModePolicy.isAutomatic(for: nil))
    }

    func testDeveloperCapturePolicyClampsSelectionAndRejectsTinyDrags() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

        XCTAssertEqual(
            BrowserDeveloperCapturePolicy.captureRect(
                from: CGPoint(x: 700, y: 500),
                to: CGPoint(x: 100, y: 50),
                in: bounds
            ),
            CGRect(x: 100, y: 50, width: 600, height: 450)
        )
        XCTAssertEqual(
            BrowserDeveloperCapturePolicy.captureRect(
                from: CGPoint(x: -20, y: -40),
                to: CGPoint(x: 900, y: 700),
                in: bounds
            ),
            bounds
        )
        XCTAssertNil(
            BrowserDeveloperCapturePolicy.captureRect(
                from: CGPoint(x: 20, y: 20),
                to: CGPoint(x: 25, y: 26),
                in: bounds
            )
        )
    }

    func testDeveloperCaptureFilenameUsesTheExistingSafeExportRules() {
        XCTAssertEqual(
            BrowserDeveloperCapturePolicy.pngFilename(
                title: #" Local / Preview: "Home"? "#,
                url: URL(string: "http://localhost:3000")
            ),
            "Local - Preview- -Home-.png"
        )
        XCTAssertEqual(
            BrowserDeveloperCapturePolicy.pngFilename(
                title: " ",
                url: URL(string: "http://localhost:3000")
            ),
            "localhost.png"
        )
    }

    func testDeveloperURLUpdatesTheStoredTabOnlyForTheActivePage() {
        XCTAssertTrue(
            BrowserDeveloperNavigationPolicy.updatesSelectedTab(
                isActivePage: true
            )
        )
        XCTAssertFalse(
            BrowserDeveloperNavigationPolicy.updatesSelectedTab(
                isActivePage: false
            )
        )
    }

    func testReloadPolicyPreservesStopBehaviorAndBypassesCachesOnDemand() {
        XCTAssertEqual(
            BrowserPageReloadPolicy.action(isLoading: true, mode: .standard),
            .stop
        )
        XCTAssertEqual(
            BrowserPageReloadPolicy.action(isLoading: false, mode: .standard),
            .reload
        )
        XCTAssertEqual(
            BrowserPageReloadPolicy.action(isLoading: true, mode: .fromOrigin),
            .reloadFromOrigin
        )
        XCTAssertEqual(
            BrowserPageReloadPolicy.action(isLoading: false, mode: .fromOrigin),
            .reloadFromOrigin
        )
    }

    func testZoomStepsUseStableBrowserLevelsAndClampAtTheEnds() {
        XCTAssertEqual(BrowserPageZoomPolicy.increased(from: 1), 1.1)
        XCTAssertEqual(BrowserPageZoomPolicy.increased(from: 3), 3)
        XCTAssertEqual(BrowserPageZoomPolicy.decreased(from: 1), 0.9)
        XCTAssertEqual(BrowserPageZoomPolicy.decreased(from: 0.5), 0.5)
    }

    func testZoomPercentageLabelRoundsForDisplay() {
        XCTAssertEqual(BrowserPageZoomPolicy.percentageLabel(for: 0.67), "67%")
        XCTAssertEqual(BrowserPageZoomPolicy.percentageLabel(for: 1.25), "125%")
    }

    func testPDFExportFilenameUsesTitleThenHostAndRemovesUnsafePathCharacters() {
        XCTAssertEqual(
            BrowserPageExportPolicy.pdfFilename(
                title: #" Crest / Design: "System"? "#,
                url: URL(string: "https://example.com/page")
            ),
            "Crest - Design- -System-.pdf"
        )
        XCTAssertEqual(
            BrowserPageExportPolicy.pdfFilename(
                title: "   ",
                url: URL(string: "https://example.com/page")
            ),
            "example.com.pdf"
        )
        XCTAssertEqual(
            BrowserPageExportPolicy.pdfFilename(title: "Release.pdf", url: nil),
            "Release.pdf"
        )
    }

    func testWebArchiveFilenameUsesTheSameSafePolicyWithoutDoublingItsExtension() {
        XCTAssertEqual(
            BrowserPageExportPolicy.webArchiveFilename(
                title: #" Crest / Snapshot: "Today"? "#,
                url: URL(string: "https://example.com/page")
            ),
            "Crest - Snapshot- -Today-.webarchive"
        )
        XCTAssertEqual(
            BrowserPageExportPolicy.webArchiveFilename(
                title: "   ",
                url: URL(string: "https://example.com/page")
            ),
            "example.com.webarchive"
        )
        XCTAssertEqual(
            BrowserPageExportPolicy.webArchiveFilename(
                title: "Snapshot.webarchive",
                url: nil
            ),
            "Snapshot.webarchive"
        )
    }
}

@MainActor
final class BrowserPageActionsTests: XCTestCase {
    func testPagePoolRoutesZoomOnlyToTheActivePage() {
        let first = BrowserTab(title: "First", url: URL(string: "https://first.example"), placement: .current)
        let second = BrowserTab(title: "Second", url: URL(string: "https://second.example"), placement: .current)
        let space = makeSpace(tabs: [first, second], selectedTabID: first.id)
        let pool = BrowserPagePool()

        pool.select(tab: first, space: space)
        pool.zoomIn()
        let firstPage = pool.activePage
        pool.select(tab: second, space: space)
        pool.zoomOut()

        XCTAssertEqual(firstPage?.pageZoom, 1.1)
        XCTAssertEqual(firstPage?.webView.pageZoom, 1.1)
        XCTAssertEqual(pool.activePage?.pageZoom, 0.9)
        XCTAssertEqual(pool.activePage?.webView.pageZoom, 0.9)
        XCTAssertEqual(pool.pageZoomLabel, "90%")
    }

    func testFindPresentationRequiresALoadedPageURL() {
        let blank = BrowserTab(title: "Blank", url: nil, placement: .current)
        let loaded = BrowserTab(title: "Loaded", url: URL(string: "https://example.com"), placement: .current)
        let space = makeSpace(tabs: [blank, loaded], selectedTabID: blank.id)
        let pool = BrowserPagePool()

        pool.select(tab: blank, space: space)
        pool.presentFind()
        XCTAssertFalse(pool.activePage?.isFindPresented == true)

        pool.select(tab: loaded, space: space)
        pool.presentFind()
        XCTAssertTrue(pool.activePage?.isFindPresented == true)
        pool.activePage?.dismissFind()
        XCTAssertFalse(pool.activePage?.isFindPresented == true)
    }

    func testFindUsesNativeWebKitSearchAndClearsItsStateOnDismiss() async throws {
        let tab = BrowserTab(title: "Find", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)

        page.webView.loadHTMLString(
            "<main>Crest native find needle</main>",
            baseURL: URL(string: "https://find.crest.test")
        )
        await waitUntil { page.completedNavigationCount == 1 && page.url != nil }

        page.presentFind()
        page.find("needle")
        await waitUntil { page.findMatchState == .found }
        XCTAssertTrue(page.isFindPresented)

        page.find("missing phrase")
        await waitUntil { page.findMatchState == .notFound }

        page.dismissFind()
        XCTAssertFalse(page.isFindPresented)
        XCTAssertEqual(page.findMatchState, .idle)
    }

    func testBrowserPagesAreInspectableWithSafarisPublicDeveloperTools() throws {
        let tab = BrowserTab(title: "Developer Tools", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()

        pool.select(tab: tab, space: space)

        XCTAssertTrue(try XCTUnwrap(pool.activePage).webView.isInspectable)
    }

    func testWebInspectorAccessShowsWebKitsInspectorOnlyForInspectableContent() {
        let host = BrowserWebInspectorHost()

        XCTAssertFalse(
            BrowserWebInspectorAccess.show(
                inspectorOwner: host,
                isInspectable: false
            )
        )
        XCTAssertEqual(host.inspector.showCount, 0)

        XCTAssertTrue(
            BrowserWebInspectorAccess.show(
                inspectorOwner: host,
                isInspectable: true
            )
        )
        XCTAssertEqual(host.inspector.showCount, 1)
    }

    func testWebInspectorAccessTogglesConsoleNetworkAndElementSelection() {
        let host = BrowserWebInspectorHost()

        XCTAssertEqual(
            BrowserWebInspectorAccess.toggle(
                .console,
                currentPanel: nil,
                inspectorOwner: host,
                isInspectable: true
            ),
            .opened(.console)
        )
        XCTAssertEqual(host.inspector.showConsoleCount, 1)
        XCTAssertTrue(host.inspector.isVisible)

        XCTAssertEqual(
            BrowserWebInspectorAccess.toggle(
                .network,
                currentPanel: .console,
                inspectorOwner: host,
                isInspectable: true
            ),
            .opened(.network)
        )
        XCTAssertEqual(host.inspector.showResourcesCount, 1)

        XCTAssertEqual(
            BrowserWebInspectorAccess.toggle(
                .network,
                currentPanel: .network,
                inspectorOwner: host,
                isInspectable: true
            ),
            .closed
        )
        XCTAssertEqual(host.inspector.closeCount, 1)
        XCTAssertFalse(host.inspector.isVisible)

        XCTAssertEqual(
            BrowserWebInspectorAccess.toggle(
                .elements,
                currentPanel: .network,
                inspectorOwner: host,
                isInspectable: true
            ),
            .opened(.elements)
        )
        XCTAssertEqual(host.inspector.showCount, 1)
        XCTAssertEqual(host.inspector.toggleElementSelectionCount, 1)
        XCTAssertTrue(host.inspector.isElementSelectionActive)
    }

    func testWebInspectorToggleFailsClosedWhenContentIsNotInspectable() {
        let host = BrowserWebInspectorHost()

        XCTAssertEqual(
            BrowserWebInspectorAccess.toggle(
                .console,
                currentPanel: nil,
                inspectorOwner: host,
                isInspectable: false
            ),
            .unavailable
        )
        XCTAssertEqual(host.inspector.showConsoleCount, 0)
    }

    func testWebInspectorAccessEnablesWebKitsDeveloperExtras() {
        let preferences = BrowserWebInspectorPreferencesSpy()

        XCTAssertTrue(
            BrowserWebInspectorAccess.enableDeveloperExtras(in: preferences)
        )
        XCTAssertTrue(preferences.isEnabled)
    }

    func testReaderModeCreatesAReversibleSanitizedViewInTheExistingSpacePage() async throws {
        let tab = BrowserTab(title: "Reader", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)
        let originalWebView = page.webView
        let originalDataStore = page.webView.configuration.websiteDataStore
        let paragraph = String(
            repeating: "Crest keeps every article inside its current Space while providing a calm reading surface. ",
            count: 8
        )

        page.webView.loadHTMLString(
            """
            <html>
              <head><title>Reader Fixture</title></head>
              <body>
                <nav>Unrelated navigation that should not enter Reader Mode.</nav>
                <main>
                  <article>
                    <h1>A Space-Safe Reader</h1>
                    <p>\(paragraph)</p>
                    <p>\(paragraph)</p>
                    <button onclick="window.readerEscape = true">Unsafe control</button>
                    <iframe srcdoc="<p>Unsafe frame</p>"></iframe>
                  </article>
                </main>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://reader.crest.test/article")
        )
        await waitUntil {
            page.completedNavigationCount == 1 && page.readerModeState == .available
        }

        try await page.setReaderModeActive(true)
        let activeSnapshot = try await BrowserReaderModeController.snapshot(
            in: page.webView
        )

        XCTAssertEqual(page.readerModeState, .active)
        XCTAssertTrue(page.webView === originalWebView)
        XCTAssertTrue(page.webView.configuration.websiteDataStore === originalDataStore)
        XCTAssertTrue(activeSnapshot.isActive)
        XCTAssertEqual(activeSnapshot.title, "A Space-Safe Reader")
        XCTAssertTrue(activeSnapshot.text.contains("calm reading surface"))
        XCTAssertFalse(activeSnapshot.text.contains("Unrelated navigation"))
        XCTAssertEqual(activeSnapshot.unsafeElementCount, 0)

        try await page.setReaderModeActive(false)
        let restoredSnapshot = try await BrowserReaderModeController.snapshot(
            in: page.webView
        )

        XCTAssertEqual(page.readerModeState, .available)
        XCTAssertFalse(restoredSnapshot.isActive)
        let originalArticleExists = try await page.webView.evaluateJavaScript(
            "document.querySelector('article') !== null"
        ) as? Bool
        XCTAssertEqual(originalArticleExists, true)
    }

    func testReaderModeRejectsPagesWithoutSubstantialArticleContent() async throws {
        let tab = BrowserTab(title: "Short", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)

        page.webView.loadHTMLString(
            "<html><body><main><p>Short utility page.</p></main></body></html>",
            baseURL: URL(string: "https://reader.crest.test/utility")
        )
        await waitUntil { page.completedNavigationCount == 1 }
        await page.refreshReaderModeAvailability()

        XCTAssertEqual(page.readerModeState, .unavailable)
    }

    func testLoadedPageCreatesARealPDFDocument() async throws {
        let tab = BrowserTab(title: "PDF", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)
        page.webView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        page.webView.loadHTMLString(
            "<html><body><h1>Crest PDF Export</h1><p>Rendered by WebKit.</p></body></html>",
            baseURL: URL(string: "https://pdf.crest.test")
        )
        await waitUntil { page.completedNavigationCount == 1 && page.url != nil }

        let data = try await page.pdfData()
        let document = try XCTUnwrap(
            CGPDFDocument(CGDataProvider(data: data as CFData)!)
        )

        XCTAssertGreaterThan(data.count, 500)
        XCTAssertGreaterThanOrEqual(document.numberOfPages, 1)
    }

    func testLoadedPageCreatesARealWebKitWebArchive() async throws {
        let tab = BrowserTab(title: "Archive", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)
        page.webView.loadHTMLString(
            "<html><body><h1>Crest Web Archive</h1><p>Rendered by WebKit.</p></body></html>",
            baseURL: URL(string: "https://archive.crest.test")
        )
        await waitUntil { page.completedNavigationCount == 1 && page.url != nil }

        let data = try await page.webArchiveData()
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        let archive = try XCTUnwrap(propertyList as? [String: Any])
        let mainResource = try XCTUnwrap(archive["WebMainResource"] as? [String: Any])
        let resourceData = try XCTUnwrap(mainResource["WebResourceData"] as? Data)

        XCTAssertGreaterThan(data.count, 200)
        XCTAssertTrue(String(decoding: resourceData, as: UTF8.self).contains("Crest Web Archive"))
    }

    private func makeSpace(tabs: [BrowserTab], selectedTabID: TabID) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Test",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: selectedTabID
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        predicate: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for browser page state")
    }
}

private final class BrowserWebInspectorHost: NSObject {
    let inspector = BrowserWebInspectorSpy()

    @objc dynamic var _inspector: NSObject { inspector }
}

private final class BrowserWebInspectorSpy: NSObject {
    private(set) var showCount = 0
    private(set) var showConsoleCount = 0
    private(set) var showResourcesCount = 0
    private(set) var closeCount = 0
    private(set) var toggleElementSelectionCount = 0
    @objc private(set) dynamic var isVisible = false
    @objc private(set) dynamic var isElementSelectionActive = false

    @objc func show() {
        showCount += 1
        isVisible = true
    }

    @objc func showConsole() {
        showConsoleCount += 1
        isVisible = true
    }

    @objc func showResources() {
        showResourcesCount += 1
        isVisible = true
    }

    @objc func close() {
        closeCount += 1
        isVisible = false
        isElementSelectionActive = false
    }

    @objc func toggleElementSelection() {
        toggleElementSelectionCount += 1
        isElementSelectionActive.toggle()
    }
}

private final class BrowserWebInspectorPreferencesSpy: NSObject {
    private(set) var isEnabled = false

    @objc(_setDeveloperExtrasEnabled:)
    func setDeveloperExtrasEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}
