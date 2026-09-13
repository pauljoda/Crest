import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserWindowSceneModelTests: XCTestCase {
    func testColdStartupLeavesTabsUnselectedRegardlessOfLegacyPreference() {
        for behavior in [
            BrowserStartupBehavior.showStartPage,
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

            XCTAssertFalse(model.navigation.compactShowsPage)
            XCTAssertNil(model.browser.selectedTab)
            XCTAssertTrue(model.browser.session.spaces.allSatisfy { $0.selectedTabID == nil })
            XCTAssertEqual(
                model.browser.session.spaces.flatMap(\.tabs).map(\.id),
                rootBrowser.session.spaces.flatMap(\.tabs).map(\.id)
            )
            XCTAssertEqual(model.pages.residentPageCount, 0)
        }
    }

    func testSetupLoadsItsNativeRuntimeBeforeOpeningTheDefaultStartupBrowser() async throws {
        let rootBrowser = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true))
        let model = MobileBrowserWindowSceneModel(
            id: BrowserWindowID(), rootBrowser: rootBrowser, permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry, spaceAccess: BrowserSpaceAccessController(), tabStateArchive: nil,
            windowStatePersistence: InMemoryBrowserWindowStatePersistence(), startupBehavior: .showStartPage,
            monitorsMemoryPressure: false, usesEphemeralWebsiteDataStores: true)
        model.privateBrowser.openNewTab(url: try XCTUnwrap(URL(string: "https://private.example")))
        let privateSession = model.privateBrowser.session
        let progress = BrowserOnboardingProgressStore(persistence: InMemoryBrowserOnboardingProgressPersistence())
        var assignment: BrowserTabRuntimeAssignment?
        let result = await BrowserOnboardingCompletion.complete(
            request: .firstRun, browser: model.browser, progress: progress, spaceAccess: model.spaceAccess,
            willComplete: { guide in
                XCTAssertTrue(progress.isLaunchGateActive)
                guard let guide else { return XCTFail("Setup did not create a guide") }
                assignment = guide
                XCTAssertTrue(model.presentGettingStartedAfterSetup(matching: guide))
                XCTAssertNotNil(model.pages.nativeTabs.runtime(matching: guide, content: .gettingStarted))
                XCTAssertTrue(model.navigation.compactShowsPage)
            })
        let guide = try XCTUnwrap(assignment)
        XCTAssertEqual(result, .completed(guide: guide))
        XCTAssertEqual(model.browser.session.spaces.first?.id, guide.spaceID)
        XCTAssertNil(model.pages.activePage)
        XCTAssertEqual(model.privateBrowser.session, privateSession)
        model.navigation.adapt(to: .compact)
        XCTAssertTrue(model.navigation.compactShowsPage)
        XCTAssertFalse(
            model.presentGettingStartedAfterSetup(
                matching:
                    BrowserTabRuntimeAssignment(tabID: guide.tabID, spaceID: guide.spaceID, profileID: UUID())))
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

        let tabID = try XCTUnwrap(model.browser.selectedSpace?.tabs.first?.id)
        model.browser.selectTab(tabID)
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
