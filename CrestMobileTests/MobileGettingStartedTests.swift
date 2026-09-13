import XCTest

@testable import CrestMobile

@MainActor
final class MobileGettingStartedTests: XCTestCase {
    func testMobileNativeRuntimeSurvivesSelectionAndUnloadsIndependentlyOfWebKit() async throws {
        let browser = BrowserStore.preview()
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let id = try XCTUnwrap(browser.openGettingStarted())
        pages.select(session: browser.session)
        let space = try XCTUnwrap(browser.selectedSpace)
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profile.id)
        let runtime = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertNil(pages.activePage)
        let state = runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        state.lesson = 2
        browser.openNewTab()
        pages.select(session: browser.session)
        XCTAssertNil(pages.prepareResidentPage(for: id, in: browser.session))
        XCTAssertTrue(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted) === runtime)
        browser.selectTab(id)
        pages.select(session: browser.session)
        XCTAssertEqual(state.lesson, 2)
        pages.handleMemoryPressure(.critical)
        await pages.waitForPendingMemoryPressureResponse()
        XCTAssertTrue(pages.nativeTabs.contains(assignment))
        XCTAssertFalse(
            pages.closeDurablePage(
                BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: UUID()), discardState: false))
        XCTAssertTrue(pages.unloadPage(for: id, matching: BrowserSpaceRuntimeAssignment(space: space)))
        XCTAssertFalse(pages.nativeTabs.contains(assignment))
        pages.select(session: browser.session)
        let reopened = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertFalse(reopened === runtime)
        XCTAssertEqual(reopened.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }.lesson, 0)
        await pages.releaseWindowRuntime(for: space)
        XCTAssertTrue(pages.nativeTabs.tabIDs.isEmpty)
    }

    func testFinishingFirstInstallCreatesOneNativeSavedGuide() throws {
        let browser = BrowserStore.preview()
        let persistence = InMemoryBrowserOnboardingProgressPersistence()
        let progress = BrowserOnboardingProgressStore(persistence: persistence)
        if progress.completeSetup(for: .firstRun) { browser.openGettingStarted() }
        if progress.completeSetup(for: .firstRun) { browser.openGettingStarted() }
        let guides = try XCTUnwrap(browser.selectedSpace).tabs.filter { $0.nativeContent == .gettingStarted }
        XCTAssertEqual(guides.count, 1)
        XCTAssertEqual(guides.first?.placement, .saved)
        XCTAssertNil(guides.first?.url)
        XCTAssertEqual(browser.selectedTab?.nativeContent, .gettingStarted)
    }

    func testSetupReplayAndForcedWelcomeDoNotReopenGuide() {
        let persistence = InMemoryBrowserOnboardingProgressPersistence(hasCompletedSetup: true)
        let replay = BrowserOnboardingProgressStore(persistence: persistence, forceWelcome: true, forceSetup: true)
        XCTAssertFalse(replay.completeSetup(for: .manualSetup))
        XCTAssertFalse(replay.completeSetup(for: .firstRun))
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

    func testOnlyFullScreenPhoneWebpagesUseEdgeToEdgeInsets() {
        XCTAssertTrue(
            MobileBrowserViewportPolicy.usesEdgeToEdgeWebViewport(
                isPhone: true, presentation: .compact, sidebarPresentation: .docked))
        for sidebar in [BrowserSidebarPresentation.floating, .collapsed] {
            XCTAssertFalse(
                MobileBrowserViewportPolicy.usesEdgeToEdgeWebViewport(
                    isPhone: true, presentation: .compact, sidebarPresentation: sidebar))
        }
        for sidebar in [BrowserSidebarPresentation.docked, .floating, .collapsed] {
            XCTAssertFalse(
                MobileBrowserViewportPolicy.usesEdgeToEdgeWebViewport(
                    isPhone: true, presentation: .regular, sidebarPresentation: sidebar))
            XCTAssertFalse(
                MobileBrowserViewportPolicy.usesEdgeToEdgeWebViewport(
                    isPhone: false, presentation: .compact, sidebarPresentation: sidebar))
            XCTAssertFalse(
                MobileBrowserViewportPolicy.usesEdgeToEdgeWebViewport(
                    isPhone: false, presentation: .regular, sidebarPresentation: sidebar))
        }
    }

    func testTouchPracticePinsSavesAndNestsWithoutAffectingUserData() {
        let practice = BrowserGettingStartedPractice()
        practice.browser.pinTab(practice.mailID)
        practice.browser.saveTab(practice.trailID)
        practice.addFolder(nested: true)
        XCTAssertEqual(practice.space.folders.count, 2)
        XCTAssertNotNil(practice.space.folders.last?.parentID)
        XCTAssertTrue(practice.tabActions.clearCurrentTabs())
        XCTAssertTrue(practice.space.currentTabs.isEmpty)
        XCTAssertTrue(practice.space.pinnedTabs.contains { $0.id == practice.mailID })
        XCTAssertTrue(practice.space.savedTabs.contains { $0.id == practice.trailID })
        XCTAssertNil(practice.browser.syncCoordinator)
        XCTAssertTrue(practice.browser.persistence is InMemoryBrowserSessionPersistence)
    }

}
