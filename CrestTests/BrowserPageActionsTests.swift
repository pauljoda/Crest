import XCTest

@testable import Crest

final class BrowserPageZoomAndDeveloperModeTests: XCTestCase {
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
                URL(string: value)?.isLocalDevelopmentAddress == true,
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
                URL(string: value)?.isLocalDevelopmentAddress == true,
                value
            )
        }
    }

    func testDefaultZoomPreservesIntermediateValuesAndClampsToItsOwnBounds() {
        XCTAssertEqual(BrowserDefaultPageZoomStore.defaultLevel, 1)
        XCTAssertEqual(BrowserDefaultPageZoomStore.normalized(0.1), 0.25)
        XCTAssertEqual(BrowserDefaultPageZoomStore.normalized(0.7), 0.7)
        XCTAssertEqual(BrowserDefaultPageZoomStore.normalized(1.23456), 1.23456)
        XCTAssertEqual(BrowserDefaultPageZoomStore.normalized(9), 5)
        XCTAssertEqual(BrowserDefaultPageZoomStore.normalized(.nan), 1)
        XCTAssertEqual(BrowserDefaultPageZoomStore.normalized(.infinity), 1)
        XCTAssertEqual(BrowserDefaultPageZoomStore.normalized(-.infinity), 1)
        for level in CGFloat.pageZoomLevels {
            XCTAssertEqual(BrowserDefaultPageZoomStore.normalized(level), level)
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
        let first = TabState.Seed(title: "Preview", url: nil, placement: .current)
        let second = TabState.Seed(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [first, second])
        let pool = BrowserPagePool(browser: .hostingPages(SessionState.Seed(spaces: [space])))
        pool.present(tab: first.id, in: space.id)
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
        pool.present(tab: second.id, in: space.id)
        XCTAssertNil(pool.activePage?.developerViewport)
        pool.present(tab: first.id, in: space.id)
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
        let first = TabState.Seed(
            title: "First",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let second = TabState.Seed(
            title: "Second",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let space = makeSpace(
            tabs: [first, second]
        )
        let pool = BrowserPagePool(
            browser: .hostingPages(SessionState.Seed(spaces: [space])), pageZoomPreferences: preferences)

        pool.present(tab: first.id, in: space.id)
        let firstPage = try XCTUnwrap(pool.activePage)
        XCTAssertEqual(firstPage.pageZoom, 1.00001)
        XCTAssertEqual(firstPage.webView.pageZoom, 1.00001)

        pool.present(tab: second.id, in: space.id)
        let secondPage = try XCTUnwrap(pool.activePage)
        XCTAssertEqual(secondPage.pageZoom, 1.00001)
        pool.present(tab: first.id, in: space.id)

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

        pool.commandPage?.zoomIn()
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
        pool.commandPage?.resetZoom()
        XCTAssertEqual(firstPage.pageZoom, 2)

        pool.present(tab: second.id, in: space.id)
        XCTAssertTrue(pool.activePage === secondPage)
        XCTAssertEqual(secondPage.pageZoom, 2)
        pool.commandPage?.zoomOut()
        XCTAssertEqual(secondPage.pageZoom, 1.75)

        pool.unloadPage(for: second.id)
        pool.present(tab: second.id, in: space.id)
        XCTAssertEqual(pool.activePage?.pageZoom, 2)
        XCTAssertFalse(pool.activePage === secondPage)
    }

    func testCommandPageActsOnActiveQuickWindowWhenInFront() throws {
        let first = TabState.Seed(
            title: "First",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let space = makeSpace(tabs: [first])
        let pool = BrowserPagePool(
            browser: .hostingPages(SessionState.Seed(spaces: [space]))
        )
        pool.present(tab: first.id, in: space.id)
        let tabPage = try XCTUnwrap(pool.activePage)
        XCTAssertTrue(pool.commandPage === tabPage)

        let lease = try XCTUnwrap(
            pool.makeTransientPageLease(
                url: try XCTUnwrap(URL(string: "about:blank#quick")),
                in: try XCTUnwrap(pool.browser.spaceModel(space.id))
            )
        )
        defer { lease.release() }
        let quickPage = try XCTUnwrap(lease.page)

        var quickInFront = false
        pool.isQuickWindowInFront = { quickInFront }
        pool.activeQuickWindowPage = { quickPage }

        XCTAssertTrue(pool.commandPage === tabPage)

        quickInFront = true
        XCTAssertTrue(pool.commandPage === quickPage)
        XCTAssertFalse(pool.commandPage === tabPage)

        pool.commandPage?.zoomIn()
        XCTAssertEqual(quickPage.pageZoom, 1.1)
        XCTAssertEqual(tabPage.pageZoom, 1.0)

        quickInFront = false
        XCTAssertTrue(pool.commandPage === tabPage)
    }

    func testCommandActionsActOnQuickWindowPageWhenInFront() throws {
        let first = TabState.Seed(
            title: "Start Page",
            url: nil,
            placement: .current
        )
        let space = makeSpace(tabs: [first])
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let pool = BrowserPagePool(browser: browser)
        pool.present(tab: first.id, in: space.id)

        let lease = try XCTUnwrap(
            pool.makeTransientPageLease(
                url: try XCTUnwrap(URL(string: "about:blank#quick")),
                in: try XCTUnwrap(pool.browser.spaceModel(space.id))
            )
        )
        defer { lease.release() }
        let quickPage = try XCTUnwrap(lease.page)

        var quickInFront = true
        pool.isQuickWindowInFront = { quickInFront }
        pool.activeQuickWindowPage = { quickPage }

        let chrome = BrowserChromeState(sidebarIsPresented: false)
        let actions = BrowserCommandActions(
            browser: browser,
            pages: pool,
            chrome: chrome,
            windows: nil
        )

        XCTAssertTrue(actions.canPerform(.reloadPage))
        XCTAssertTrue(actions.canPerform(.reloadFromOrigin))
        XCTAssertTrue(actions.canPerform(.zoomIn))

        actions.zoomIn()
        XCTAssertEqual(quickPage.pageZoom, 1.1)
        actions.resetZoom()
        XCTAssertEqual(quickPage.pageZoom, 1.0)

        quickInFront = false
        XCTAssertFalse(actions.canPerform(.reloadPage))
        XCTAssertFalse(actions.canPerform(.reloadFromOrigin))
    }

    private func makeSpace(tabs: [TabState.Seed]) -> SpaceState.Seed {
        SpaceState.Seed(name: "Test", symbol: "circle", accent: .indigo, tabs: tabs)
    }
}
