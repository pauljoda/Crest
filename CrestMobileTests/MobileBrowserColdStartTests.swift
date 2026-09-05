import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserColdStartTests: XCTestCase {
    func testFloatingColdLaunchPreservesSplitMembershipAndWarmUserSelection() throws {
        var session = BrowserSession.preview
        let group = SplitGroupID()
        session.spaces[0].tabs[0].placement = .current
        session.spaces[0].tabs[1].placement = .current
        session.spaces[0].tabs[0].splitGroupID = group
        session.spaces[0].tabs[1].splitGroupID = group
        let root = BrowserStore(session: session, persistence: InMemoryBrowserSessionPersistence())
        let id = BrowserWindowID()
        let persistence = InMemoryBrowserWindowStatePersistence()
        persistence.save(
            BrowserWindowState(
                id: id,
                selectedSpaceID: session.selectedSpaceID,
                selectedTabIDsBySpace: [:],
                sidebarIsPresented: false
            ))
        let model = MobileBrowserWindowSceneModel(
            id: id,
            rootBrowser: root,
            permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: MobileBrowserPageStoreRegistry(primary: MobileBrowserPageStore()),
            spaceAccess: BrowserSpaceAccessController(),
            tabStateArchive: nil,
            windowStatePersistence: persistence,
            startupBehavior: .lastActiveTab,
            monitorsMemoryPressure: false,
            usesEphemeralWebsiteDataStores: true
        )
        XCTAssertTrue(model.navigation.compactShowsPage)
        XCTAssertFalse(model.navigation.regularSidebarIsDocked)
        XCTAssertNil(model.browser.selectedTab)
        XCTAssertEqual(model.browser.session.spaces[0].tabs.prefix(2).map(\.splitGroupID), [group, group])
        let choice = try XCTUnwrap(model.browser.selectedSpace?.tabs.first?.id)
        model.browser.selectTab(choice)
        model.prepareForInactiveScene()
        model.prepareForBackgroundScene()
        model.activateWindow()
        XCTAssertEqual(model.browser.selectedTab?.id, choice)
    }

    func testEmptyPaletteModelRoutesURLResultThroughTheSpaceActions() throws {
        let root = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let window = root.makeWindowStore(restoresTabSelection: false)
        let space = try XCTUnwrap(window.selectedSpace)
        let actions = BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: space),
            browser: window,
            accessController: BrowserSpaceAccessController(),
            didSelectTab: {}
        )
        let model = BrowserCommandPaletteModel(
            space: space,
            selectedTabID: nil,
            initialQuery: "https://example.com/new",
            commands: nil,
            isSourceAvailable: { _ in
                XCTFail("No source tab exists")
                return false
            },
            selectTab: { _, _ in
                XCTFail("No source tab exists")
                return false
            },
            openURL: { _, _ in
                XCTFail("No source tab exists")
                return false
            },
            dismiss: {},
            emptySelectionActions: actions
        )
        model.activateSelectedResult()
        XCTAssertEqual(window.selectedTab?.url?.absoluteString, "https://example.com/new")
    }

    func testAutomaticCleanupDoesNotSelectATabInAnEmptyWindow() {
        let root = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let window = root.makeWindowStore(restoresTabSelection: false)
        window.sweepExpiredBrowsingData()
        XCTAssertNil(window.selectedTab)
    }

    func testDelayedPublicationKeepsEmptySelectionAndPreservesManualChoice() throws {
        let root = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let window = root.makeWindowStore(restoresTabSelection: false)
        let formerSelection = try XCTUnwrap(root.selectedTab?.id)
        root.session.closeTab(formerSelection)
        root.persist()
        XCTAssertNil(window.selectedTab)

        let choice = try XCTUnwrap(window.selectedSpace?.tabs.first?.id)
        window.selectTab(choice)
        root.persist()
        XCTAssertEqual(window.selectedTab?.id, choice)
        XCTAssertEqual(root.makeWindowStore().selectedTab?.id, choice)
    }

    func testNewTabPaletteCreatesOneTabAndRejectsStaleActions() throws {
        let root = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let window = root.makeWindowStore(restoresTabSelection: false)
        let space = try XCTUnwrap(window.selectedSpace)
        var activationCount = 0
        let actions = BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: space),
            browser: window,
            accessController: BrowserSpaceAccessController(),
            didSelectTab: { activationCount += 1 }
        )
        let url = try XCTUnwrap(URL(string: "https://example.com/new"))
        XCTAssertTrue(actions.openURL(url))
        XCTAssertEqual(window.selectedSpace?.tabs.count, space.tabs.count + 1)
        XCTAssertEqual(window.selectedTab?.url, url)
        XCTAssertEqual(activationCount, 1)
        XCTAssertFalse(actions.openURL(url))
        XCTAssertEqual(activationCount, 1)
    }

    func testEmptyPaletteRejectsAnotherSpaceAndSelectsAnExistingTabWithoutCreatingOne() throws {
        let root = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let window = root.makeWindowStore(restoresTabSelection: false)
        let space = try XCTUnwrap(window.selectedSpace)
        let actions = BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: space),
            browser: window,
            accessController: BrowserSpaceAccessController(),
            didSelectTab: {}
        )
        let tab = try XCTUnwrap(space.tabs.first)
        let target = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        let other = try XCTUnwrap(window.session.spaces.last)
        window.selectSpace(other.id)
        XCTAssertFalse(actions.selectTab(target))
        window.selectSpace(space.id)
        window.session.clearTabSelection(in: space.id)
        XCTAssertTrue(actions.selectTab(target))
        XCTAssertEqual(window.selectedSpace?.tabs.count, space.tabs.count)
        XCTAssertEqual(window.selectedTab?.id, tab.id)
    }
}
