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
                session: .preview
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
                windowLayouts: BrowserWindowLayouts(defaults: nil),
                startupBehavior: behavior,
                monitorsMemoryPressure: false
            )

            XCTAssertFalse(model.navigation.compactShowsPage)
            XCTAssertNil(model.browser.selectedTab)
            XCTAssertTrue(model.browser.session.spaces.allSatisfy { model.browser.selectedTabID(in: $0.id) == nil })
            XCTAssertEqual(
                model.browser.session.spaces.flatMap(\.tabs).map(\.id),
                rootBrowser.session.spaces.flatMap(\.tabs).map(\.id)
            )
            XCTAssertEqual(model.pages.residentPageCount, 0)
        }
    }

    func testSetupLoadsItsNativeRuntimeBeforeOpeningTheDefaultStartupBrowser() async throws {
        let rootBrowser = BrowserStore(session: .preview)
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true))
        let model = MobileBrowserWindowSceneModel(
            id: BrowserWindowID(), rootBrowser: rootBrowser, permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry, spaceAccess: BrowserSpaceAccessController(), tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil), startupBehavior: .showStartPage,
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
            session: .preview
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
            windowLayouts: BrowserWindowLayouts(defaults: nil),
            startupBehavior: .lastActiveTab,
            monitorsMemoryPressure: false,
            usesEphemeralWebsiteDataStores: true
        )

        let tabID = try XCTUnwrap(model.browser.selectedSpace?.tabs.first?.id)
        model.browser.selectTab(tabID)
        model.pages.select(session: model.browser.presented)

        let store = try XCTUnwrap(
            model.pages.activePage?.webView.configuration.websiteDataStore
        )
        XCTAssertFalse(store.isPersistent)
        XCTAssertNil(store.identifier)
    }

    func testScenesShareBrowsingEditsButKeepSelectionPagesAndPrivateSessionsIndependent() throws {
        let url = try XCTUnwrap(URL(string: "about:blank"))
        let sharedTab = BrowserTab(title: "Shared", url: url, placement: .current)
        let otherTab = BrowserTab(title: "Other", url: url, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Windows", symbol: "globe", accent: .indigo,
            folders: [], tabs: [sharedTab, otherTab])
        let root = BrowserStore(
            session: BrowserSession(spaces: [space]),
            showing: space.id, tabs: [space.id: sharedTab.id])
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true))
        let permissionCenter = BrowserSitePermissionCenter()
        let spaceAccess = BrowserSpaceAccessController()
        let windowLayouts = BrowserWindowLayouts(defaults: nil)
        func makeScene() -> MobileBrowserWindowSceneModel {
            MobileBrowserWindowSceneModel(
                id: BrowserWindowID(), rootBrowser: root, permissionCenter: permissionCenter,
                pageStoreRegistry: registry, spaceAccess: spaceAccess, tabStateArchive: nil,
                windowLayouts: windowLayouts, startupBehavior: .lastActiveTab,
                monitorsMemoryPressure: false, usesEphemeralWebsiteDataStores: true)
        }
        let first = makeScene()
        let second = makeScene()
        defer {
            first.pages.reconcile(validTabIDs: [])
            second.pages.reconcile(validTabIDs: [])
        }
        first.browser.selectTab(sharedTab.id)
        second.browser.selectTab(otherTab.id)

        first.browser.pinTab(sharedTab.id)

        XCTAssertTrue(first.browser.family === second.browser.family)
        XCTAssertEqual(second.browser.selectedSpace?.pinnedTabs.map(\.id), [sharedTab.id])
        XCTAssertEqual(first.browser.selectedTab?.id, sharedTab.id)
        XCTAssertEqual(second.browser.selectedTab?.id, otherTab.id)

        first.pages.select(session: first.browser.presented)
        second.browser.selectTab(sharedTab.id)
        second.pages.select(session: second.browser.presented)
        let firstPage = try XCTUnwrap(first.pages.activePage)
        let secondPage = try XCTUnwrap(second.pages.activePage)
        XCTAssertFalse(first.pages === second.pages)
        XCTAssertFalse(firstPage === secondPage)
        XCTAssertFalse(firstPage.webView === secondPage.webView)
        XCTAssertEqual(firstPage.tabID, secondPage.tabID)
        XCTAssertEqual(firstPage.profileID, secondPage.profileID)
        XCTAssertFalse(firstPage.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(secondPage.webView.configuration.websiteDataStore.isPersistent)
        first.pages.reconcile(validTabIDs: [])
        XCTAssertNil(first.pages.activePage)
        XCTAssertTrue(second.pages.activePage === secondPage)
        XCTAssertNotNil(second.browser.selectedTab)

        XCTAssertFalse(first.privateBrowser.family === second.privateBrowser.family)
        XCTAssertFalse(first.privateBrowser.family === root.family)
        XCTAssertFalse(second.privateBrowser.family === root.family)
        let secondPrivateSession = second.privateBrowser.session
        let normalSession = root.session
        let privateTabID = try XCTUnwrap(first.privateBrowser.openNewTab(url: url))
        XCTAssertTrue(first.privateBrowser.session.tabIDs.contains(privateTabID))
        XCTAssertEqual(second.privateBrowser.session, secondPrivateSession)
        XCTAssertEqual(root.session, normalSession)
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
