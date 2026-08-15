import XCTest
@testable import CrestMobile

@MainActor
final class MobileBrowserWindowSceneModelTests: XCTestCase {
    func testStartupWaitsInTheTabViewerUnlessLastActiveTabIsEnabled() {
        for behavior in [
            BrowserStartupBehavior.waitForTabSelection,
            .lastActiveTab,
        ] {
            let rootBrowser = BrowserStore(
                session: .preview,
                persistence: InMemoryBrowserSessionPersistence()
            )
            let registry = MobileBrowserPageStoreRegistry(
                primary: MobileBrowserPageStore()
            )
            let model = MobileBrowserWindowSceneModel(
                id: BrowserWindowID(),
                rootBrowser: rootBrowser,
                permissionCenter: BrowserSitePermissionCenter(),
                pageStoreRegistry: registry,
                spaceAccess: BrowserSpaceAccessController(),
                tabStateArchive: nil,
                windowStatePersistence: InMemoryBrowserWindowStatePersistence(),
                startupBehavior: behavior,
                monitorsMemoryPressure: false
            )

            XCTAssertEqual(
                model.navigation.compactShowsPage,
                behavior.activatesRestoredTab
            )
            XCTAssertEqual(model.pages.residentPageCount, 0)
        }
    }

    func testIsolatedWindowModelUsesOnlyEphemeralWebsiteData() throws {
        let rootBrowser = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence()
        )
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(
                usesEphemeralWebsiteDataStores: true
            )
        )
        let model = MobileBrowserWindowSceneModel(
            id: BrowserWindowID(),
            rootBrowser: rootBrowser,
            permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry,
            spaceAccess: BrowserSpaceAccessController(),
            tabStateArchive: nil,
            windowStatePersistence: InMemoryBrowserWindowStatePersistence(),
            startupBehavior: .lastActiveTab,
            monitorsMemoryPressure: false,
            usesEphemeralWebsiteDataStores: true
        )

        model.pages.select(session: model.browser.session)

        let store = try XCTUnwrap(
            model.pages.activePage?.webView.configuration.websiteDataStore
        )
        XCTAssertFalse(store.isPersistent)
        XCTAssertNil(store.identifier)
    }

    func testQuickWindowDecisionResolvesToTheRequestedSpace() throws {
        let session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.spaces.first?.id)
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))

        let route = MobileBrowserWindowSceneRoute.resolve(
            url: url,
            decision: .quickWindow(spaceID: spaceID),
            session: session
        )

        XCTAssertEqual(
            route,
            .quickWindow(url: url, spaceID: spaceID)
        )
    }

    func testSpaceDecisionResolvesToTheRequestedSpace() throws {
        let session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.spaces.last?.id)
        let url = try XCTUnwrap(URL(string: "https://webkit.org/blog"))

        let route = MobileBrowserWindowSceneRoute.resolve(
            url: url,
            decision: .space(spaceID),
            session: session
        )

        XCTAssertEqual(route, .space(url: url, spaceID: spaceID))
    }

    func testExternalRouteRejectsUnsupportedSchemes() throws {
        let session = BrowserSession.preview
        let spaceID = try XCTUnwrap(session.spaces.first?.id)
        let url = try XCTUnwrap(URL(string: "file:///tmp/private.txt"))

        let route = MobileBrowserWindowSceneRoute.resolve(
            url: url,
            decision: .space(spaceID),
            session: session
        )

        XCTAssertNil(route)
    }

    func testExternalRouteRejectsASpaceOutsideTheWindowSession() throws {
        let session = BrowserSession.preview
        let url = try XCTUnwrap(URL(string: "https://example.com"))

        let route = MobileBrowserWindowSceneRoute.resolve(
            url: url,
            decision: .space(SpaceID()),
            session: session
        )

        XCTAssertNil(route)
    }
}
