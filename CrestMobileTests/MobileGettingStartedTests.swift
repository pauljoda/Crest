import XCTest

@testable import CrestMobile

@MainActor
final class MobileGettingStartedTests: XCTestCase {
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
