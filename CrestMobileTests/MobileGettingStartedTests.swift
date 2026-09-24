import XCTest

@testable import CrestMobile

@MainActor
final class MobileGettingStartedTests: XCTestCase {
    func testMobileNativeRuntimeSurvivesSelectionAndUnloadsIndependentlyOfWebKit() async throws {
        let browser = BrowserStore.hostingPages()
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let id = try XCTUnwrap(browser.openGettingStarted())
        pages.select(session: browser.presented)
        let space = try XCTUnwrap(browser.selectedSpace)
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profile.id)
        let runtime = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertNil(pages.activePage)
        let state = runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        state.lesson = 2
        browser.openNewTab()
        pages.select(session: browser.presented)
        XCTAssertNil(pages.prepareResidentPage(for: id, in: browser.presented))
        XCTAssertTrue(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted) === runtime)
        browser.selectTab(id)
        pages.select(session: browser.presented)
        XCTAssertEqual(state.lesson, 2)
        pages.handleMemoryPressure(.critical)
        await pages.waitForPendingMemoryPressureResponse()
        XCTAssertTrue(pages.nativeTabs.contains(assignment))
        XCTAssertFalse(
            pages.closeDurablePage(
                BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: UUID()), discardState: false))
        XCTAssertTrue(pages.unloadPage(for: id, matching: BrowserSpaceRuntimeAssignment(space: space)))
        XCTAssertFalse(pages.nativeTabs.contains(assignment))
        pages.select(session: browser.presented)
        let reopened = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertFalse(reopened === runtime)
        XCTAssertEqual(reopened.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }.lesson, 0)
        await pages.releaseWindowRuntime(for: space)
        XCTAssertTrue(pages.nativeTabs.tabIDs.isEmpty)
    }

    func testSetupPresentsGuideBeforeBrowserWidthIsResolved() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .regular)
        navigation.presentSelectedTabAfterSetup()
        navigation.adapt(to: .compact)

        XCTAssertTrue(navigation.compactShowsPage)
        XCTAssertFalse(navigation.compactTabViewerChromeIsVisible)
        XCTAssertTrue(navigation.regularSidebarIsDocked)
        navigation.completePagePresentation()
        XCTAssertTrue(navigation.compactPageIsFullyPresented)
    }

}
