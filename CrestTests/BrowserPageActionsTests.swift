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

    func testDefaultZoomPreservesIntermediateValuesAndClampsToItsOwnBounds() {
        XCTAssertEqual(BrowserPageZoomPolicy.defaultLevel, 1)
        XCTAssertEqual(BrowserPageZoomPolicy.normalizedDefault(0.1), 0.25)
        XCTAssertEqual(BrowserPageZoomPolicy.normalizedDefault(0.7), 0.7)
        XCTAssertEqual(BrowserPageZoomPolicy.normalizedDefault(1.23456), 1.23456)
        XCTAssertEqual(BrowserPageZoomPolicy.normalizedDefault(9), 5)
        XCTAssertEqual(BrowserPageZoomPolicy.normalizedDefault(.nan), 1)
        XCTAssertEqual(BrowserPageZoomPolicy.normalizedDefault(.infinity), 1)
        XCTAssertEqual(BrowserPageZoomPolicy.normalizedDefault(-.infinity), 1)
        for level in BrowserPageZoomPolicy.levels {
            XCTAssertEqual(BrowserPageZoomPolicy.normalizedDefault(level), level)
        }
    }

}

@MainActor
final class BrowserDefaultPageZoomStoreTests: XCTestCase {
    func testUserDefaultsPersistenceSurvivesStoreRecreation() throws {
        let suiteName = "BrowserDefaultPageZoomStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = BrowserDefaultPageZoomStore(
            persistence: UserDefaultsBrowserDefaultPageZoomPersistence(
                defaults: defaults
            )
        )
        XCTAssertEqual(first.defaultZoom, 1)

        first.defaultZoom = 1.23456
        first.defaultZoom = 1.23457

        let restored = BrowserDefaultPageZoomStore(
            persistence: UserDefaultsBrowserDefaultPageZoomPersistence(
                defaults: defaults
            )
        )
        XCTAssertEqual(restored.defaultZoom, 1.23457)
    }

    func testInvalidPersistedAndSliderValuesClampToSupportedRange() {
        let persistence = InMemoryBrowserDefaultPageZoomPersistence(zoom: -1)
        let store = BrowserDefaultPageZoomStore(persistence: persistence)

        XCTAssertEqual(store.defaultZoom, 0.25)
        XCTAssertEqual(persistence.load(), 0.25)

        store.defaultZoom = -100
        XCTAssertEqual(store.defaultZoom, 0.25)

        store.defaultZoom = 100
        XCTAssertEqual(store.defaultZoom, 5)

        store.defaultZoom = .infinity
        XCTAssertEqual(store.defaultZoom, 1)
        XCTAssertEqual(persistence.load(), 1)
    }
}

@MainActor
final class BrowserPageActionsTests: XCTestCase {
    func testDeveloperPreviewBelongsToTheLivePageAndHidingToolbarRestoresNormalMode() throws {
        let first = BrowserTab(title: "Preview", url: nil, placement: .current)
        let second = BrowserTab(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [first, second], selectedTabID: first.id)
        let pool = BrowserPagePool()
        pool.select(tab: first, space: space)
        let page = try XCTUnwrap(pool.activePage)
        let webView = page.webView
        page.zoomIn()
        let normalZoom = page.pageZoom
        page.setDeveloperToolbarVisible(true)
        page.developerViewport = .phone
        XCTAssertEqual(webView.pageZoom, 1)
        XCTAssertFalse(page.zoomIn())
        XCTAssertFalse(page.zoomOut())
        XCTAssertFalse(page.resetZoom())
        page.prepareForNavigation(to: URL(string: "https://example.com"))
        pool.select(tab: second, space: space)
        XCTAssertNil(pool.activePage?.developerViewport)
        pool.select(tab: first, space: space)
        XCTAssertTrue(pool.activePage === page)
        XCTAssertTrue(page.webView === webView)
        XCTAssertEqual(page.developerViewport, .phone)
        XCTAssertTrue(page.isDeveloperModeEnabled)
        page.setDeveloperToolbarVisible(false)
        XCTAssertNil(page.developerViewport)
        XCTAssertFalse(page.isDeveloperModeEnabled)
        XCTAssertEqual(page.pageZoom, normalZoom)
        XCTAssertEqual(webView.pageZoom, normalZoom)
    }

    func testDefaultZoomFollowsResidentAndRecreatedPageLifecycles() throws {
        let preferences = BrowserDefaultPageZoomStore(
            persistence: InMemoryBrowserDefaultPageZoomPersistence(zoom: 1.00001)
        )
        let first = BrowserTab(
            title: "First",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let second = BrowserTab(
            title: "Second",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let space = makeSpace(
            tabs: [first, second],
            selectedTabID: first.id
        )
        let pool = BrowserPagePool(pageZoomPreferences: preferences)

        pool.select(tab: first, space: space)
        let firstPage = try XCTUnwrap(pool.activePage)
        XCTAssertEqual(firstPage.pageZoom, 1.00001)
        XCTAssertEqual(firstPage.webView.pageZoom, 1.00001)

        pool.select(tab: second, space: space)
        let secondPage = try XCTUnwrap(pool.activePage)
        XCTAssertEqual(secondPage.pageZoom, 1.00001)
        pool.select(tab: first, space: space)

        for zoom: CGFloat in [0.25, 5, 1.50001, 1.50002] {
            preferences.defaultZoom = zoom
            XCTAssertEqual(firstPage.pageZoom, zoom)
            XCTAssertEqual(firstPage.webView.pageZoom, zoom)
            XCTAssertEqual(secondPage.webView.pageZoom, zoom)
        }

        preferences.defaultZoom = 1.5
        XCTAssertEqual(firstPage.pageZoom, 1.5)
        XCTAssertEqual(
            secondPage.pageZoom,
            1.5,
            "Inactive resident pages must adopt the new global baseline."
        )

        pool.zoomIn()
        XCTAssertEqual(firstPage.pageZoom, 1.75)
        firstPage.load(
            try XCTUnwrap(URL(string: "about:blank#navigated"))
        )
        XCTAssertEqual(
            firstPage.pageZoom,
            1.75,
            "A page-local zoom override survives navigation in the same page."
        )

        preferences.defaultZoom = 2
        XCTAssertEqual(
            firstPage.pageZoom,
            1.75,
            "Changing the baseline must not discard a temporary page override."
        )
        XCTAssertEqual(secondPage.pageZoom, 2)
        pool.resetZoom()
        XCTAssertEqual(firstPage.pageZoom, 2)

        pool.select(tab: second, space: space)
        XCTAssertTrue(pool.activePage === secondPage)
        XCTAssertEqual(secondPage.pageZoom, 2)
        pool.zoomOut()
        XCTAssertEqual(secondPage.pageZoom, 1.75)

        pool.unloadPage(for: second.id)
        pool.select(tab: second, space: space)
        XCTAssertEqual(pool.activePage?.pageZoom, 2)
        XCTAssertFalse(pool.activePage === secondPage)
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
        let originalArticleExists =
            try await page.webView.evaluateJavaScript(
                "document.querySelector('article') !== null"
            ) as? Bool
        XCTAssertEqual(originalArticleExists, true)
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
