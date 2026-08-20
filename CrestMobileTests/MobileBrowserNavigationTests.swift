import SwiftUI
import UIKit
import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserNavigationTests: XCTestCase {
    func testMobileStartPageUsesOnBrandTextAcrossLayouts() {
        XCTAssertEqual(
            MobileStartPageAppearancePolicy.foregroundTone(
                usesCommandPalette: false
            ),
            .onBrand
        )
        XCTAssertEqual(
            MobileStartPageAppearancePolicy.foregroundTone(
                usesCommandPalette: true
            ),
            .onBrand
        )
    }

    func testMobileSidebarUsesSpaceForegroundAcrossLayouts() {
        XCTAssertTrue(
            MobileBrowserSidebarAppearancePolicy.usesSpaceForeground(
                for: .compactTabViewer
            )
        )
        XCTAssertTrue(
            MobileBrowserSidebarAppearancePolicy.usesSpaceForeground(
                for: .regularSidebar
            )
        )
    }

    func testMobileReloadPolicyMatchesDesktopAndKeepsHardReloadExplicit() {
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

    func testHardwareKeyboardStopLoadingUsesTheDesktopDefault() {
        XCTAssertEqual(
            MobileBrowserKeyboardShortcut.stopLoadingKey,
            KeyEquivalent(".")
        )
        XCTAssertEqual(
            MobileBrowserKeyboardShortcut.stopLoadingModifiers,
            .command
        )
    }

    func testReducedTransparencyUsesOpaqueAtmosphereAndStrongerScrims() {
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.atmosphereOpacity(
                0.22,
                reduceTransparency: true
            ),
            0
        )
        XCTAssertGreaterThanOrEqual(
            BrowserVisualAccessibilityPolicy.scrimOpacity(
                0.16,
                reduceTransparency: true
            ),
            0.5
        )
    }

    func testReducedMotionRemovesCompactSpatialEffects() {
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.spatialScale(
                0.965,
                reduceMotion: true
            ),
            1
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.spatialOffset(
                36,
                reduceMotion: true
            ),
            0
        )
    }

    func testReducedMotionDisablesMobileChromeAnimations() {
        XCTAssertNotNil(
            BrowserVisualAccessibilityPolicy.animation(
                .snappy(duration: 0.28),
                reduceMotion: false
            )
        )
        XCTAssertNil(
            BrowserVisualAccessibilityPolicy.animation(
                .snappy(duration: 0.28),
                reduceMotion: true
            )
        )
    }

    func testMobileColoredChromeChoosesAReadableForegroundInEveryAppearance() {
        let backgrounds: [Color] = [
            .blue,
            .cyan,
            .indigo,
            .green,
            .orange,
            .pink,
            .purple,
            .red,
            .teal,
            .gray,
        ]

        for colorScheme in [ColorScheme.light, .dark] {
            for background in backgrounds {
                let foreground = BrowserVisualAccessibilityPolicy.readableForeground(
                    over: background,
                    colorScheme: colorScheme
                )
                let ratio = BrowserVisualAccessibilityPolicy.contrastRatio(
                    foreground: foreground,
                    background: background,
                    colorScheme: colorScheme
                )

                XCTAssertGreaterThanOrEqual(
                    ratio,
                    4.5,
                    "\(background) must remain readable in \(colorScheme)."
                )
            }
        }
    }

    func testMobileSpaceAccessibilityReportsPositionAndOneStepAdjustment() throws {
        let session = BrowserSession.preview
        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.last)

        XCTAssertEqual(
            BrowserChromeAccessibility.spaceValue(
                spaces: session.spaces,
                selectedSpaceID: work.id
            ),
            "Work, 1 of 2"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.adjacentSpaceID(
                spaces: session.spaces,
                selectedSpaceID: work.id,
                direction: .next
            ),
            personal.id
        )
    }

    func testMobileChromeAccessibilityAnnouncesControlStateAndCounts() {
        XCTAssertEqual(
            BrowserChromeAccessibility.tabValue(isLoaded: true),
            "Loaded"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.tabValue(isLoaded: false),
            "Not loaded"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.folderValue(isExpanded: true),
            "Expanded"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.countValue(
                1,
                singular: "download",
                plural: "downloads"
            ),
            "1 download"
        )
    }

    func testMobileTabsUseSharedResidencyAppearance() {
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.tabResidencySaturation(
                isLoaded: false
            ),
            0.3
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.tabResidencyOpacity(
                isLoaded: false
            ),
            0.5
        )
    }

    func testMobileSidebarTreatsStartPagesAsUncommittedDrafts() throws {
        let space = try XCTUnwrap(BrowserSession.preview.selectedSpace)

        XCTAssertTrue(space.tabs.contains(where: \.isStartPage))
        XCTAssertFalse(space.tabSections.sidebarCurrentTabs.contains(where: \.isStartPage))
    }

    func testMobileFileExportsOfferShareAndSaveToFilesDestinations() {
        XCTAssertEqual(
            MobileBrowserFileExportDestination.allCases,
            [.share, .files]
        )
        XCTAssertEqual(MobileBrowserFileExportDestination.share.title, "Share…")
        XCTAssertEqual(
            MobileBrowserFileExportDestination.files.title,
            "Save to Files…"
        )
    }

    func testMobilePageMenuPromotesSafariStyleCommonActions() {
        XCTAssertEqual(
            MobilePageMenuLayout.primaryActions,
            [.share, .copy, .reload]
        )
    }

    func testCompactToolbarCanCollapseToADomainChipAndReexpand() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()

        navigation.hideCompactToolbar()
        XCTAssertTrue(navigation.compactToolbarIsHidden)

        navigation.showCompactToolbar()
        XCTAssertFalse(navigation.compactToolbarIsHidden)
    }

    func testOpeningAnotherCompactTabRestoresTheFullToolbar() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()
        navigation.hideCompactToolbar()

        navigation.showTabViewer()
        navigation.selectTab()

        XCTAssertFalse(navigation.compactToolbarIsHidden)
    }

    /// Toolbar swipes page Split View cards instead. A transition which really
    /// leaves the rendered Space still puts the page away first.
    func testLeavingARenderedSpaceDismissesThePageBeforeTheSwitch() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()
        navigation.hideCompactToolbar()

        navigation.prepareForSpaceSwitch()

        XCTAssertFalse(navigation.compactShowsPage)
        XCTAssertFalse(navigation.compactToolbarIsHidden)
    }

    func testLockKeepsTheFloatingPhoneSidebarOverThePage() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()
        navigation.toggleCompactSidebar()

        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)
        XCTAssertTrue(navigation.compactShowsPage)

        navigation.prepareForLockedSpace()

        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)
        XCTAssertTrue(navigation.compactShowsPage)
        XCTAssertEqual(
            navigation.finishLockedSpaceTransition(),
            .selectedPage
        )
    }

    func testLockRevealsACollapsedFloatingPhoneSidebar() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()
        navigation.toggleCompactSidebar()
        navigation.hideRegularSidebar()

        XCTAssertEqual(navigation.regularSidebarPresentation, .collapsed)

        navigation.prepareForLockedSpace()

        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)
        XCTAssertTrue(navigation.compactShowsPage)
    }

    func testLockKeepsTheDockedPhoneInItsFullscreenTabViewer() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()

        navigation.prepareForLockedSpace()

        XCTAssertEqual(navigation.regularSidebarPresentation, .docked)
        XCTAssertFalse(navigation.compactShowsPage)
        XCTAssertEqual(
            navigation.finishLockedSpaceTransition(),
            .tabViewer
        )
    }

    func testLockedFloatingSidebarDoesNotAutoDismiss() async throws {
        let navigation = MobileBrowserNavigationState(
            transientSidebarDismissalDelay: .milliseconds(10)
        )
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()
        navigation.toggleCompactSidebar()
        navigation.prepareForLockedSpace()
        navigation.handleRegularSidebarInteraction()

        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)
        XCTAssertTrue(navigation.compactShowsPage)
    }

    func testDeactivatingMobilePagePresentationRetainsButStopsPresentingItsPage() throws {
        let space = makeSpace(index: 92)
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        let session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        pages.select(session: session)
        let originalPage = try XCTUnwrap(pages.activePage)

        pages.deactivatePagePresentation()

        XCTAssertNil(pages.activePage)
        XCTAssertTrue(pages.containsResidentPage(for: originalPage.tabID))

        pages.select(session: session)
        XCTAssertTrue(try XCTUnwrap(pages.activePage) === originalPage)
    }

    func testSelectionCannotRecreateAReleasingSpacePage()
        async throws
    {
        let space = makeSpace(index: 99)
        let session = BrowserSession(
            spaces: [space],
            selectedSpaceID: space.id
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        let tabID = try XCTUnwrap(space.selectedTabID)
        pages.select(session: session)
        var retainedPage: MobileBrowserPage? = try XCTUnwrap(pages.activePage)

        let release = Task {
            await pages.releaseWindowRuntime(for: space)
        }
        for _ in 0..<1_000 where pages.containsResidentPage(for: tabID) {
            await Task.yield()
        }
        XCTAssertFalse(pages.containsResidentPage(for: tabID))

        pages.select(session: session)

        XCTAssertFalse(pages.containsResidentPage(for: tabID))
        XCTAssertNil(pages.activePage)

        withExtendedLifetime(retainedPage) {}
        retainedPage = nil
        await release.value
    }

    func testMobileSpaceSwitchingRetainsPagesUntilTheProtectedSpaceRelocks() throws {
        let firstSpace = makeSpace(index: 93)
        let secondSpace = makeSpace(index: 94)
        var session = BrowserSession(
            spaces: [firstSpace, secondSpace],
            selectedSpaceID: firstSpace.id
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )

        pages.select(session: session)
        let firstPage = try XCTUnwrap(pages.activePage)
        session.selectSpace(secondSpace.id)
        pages.select(session: session)

        XCTAssertTrue(pages.containsResidentPage(for: firstPage.tabID))
        XCTAssertTrue(
            pages.containsResidentPage(for: try XCTUnwrap(secondSpace.selectedTabID))
        )

        session.selectSpace(firstSpace.id)
        pages.select(session: session)
        XCTAssertTrue(try XCTUnwrap(pages.activePage) === firstPage)

        pages.unloadPages(in: firstSpace.id)

        XCTAssertFalse(pages.containsResidentPage(for: firstPage.tabID))
        XCTAssertTrue(
            pages.containsResidentPage(for: try XCTUnwrap(secondSpace.selectedTabID))
        )
    }

    func testCompactPageChromeFloatsOverThePagesThemeBackdrop() {
        XCTAssertTrue(MobileCompactPageChromePolicy.usesPageThemeBackdrop)
        XCTAssertFalse(MobileCompactPageChromePolicy.drawsToolbarBackground)
        XCTAssertTrue(MobileCompactPageChromePolicy.extendsWebContentBehindToolbar)
    }

    func testCompactAddressBarUsesSymmetricEdgeControls() {
        XCTAssertEqual(
            MobileCompactAddressBarLayout.pageActionsControlSize,
            MobileCompactAddressBarLayout.reloadControlSize
        )
    }

    func testCompactNewTabUsesAndFocusesTheSharedCommandPalette() {
        XCTAssertTrue(MobileStartPageSearchPolicy.usesSharedCommandPalette)
        XCTAssertTrue(MobileStartPageSearchPolicy.focusesWhenNewTabOpens)
        XCTAssertEqual(
            MobileStartPageSearchPolicy.destination(
                isStartPage: true,
                presentation: .regular
            ),
            .embeddedStartPage
        )
        XCTAssertEqual(
            MobileStartPageSearchPolicy.destination(
                isStartPage: false,
                presentation: .regular
            ),
            .overlay
        )
    }

    func testRegularBrowserUsesOneRootAtmosphereAcrossSidebarAndContent() {
        XCTAssertTrue(MobileRegularBrowserBackdropPolicy.rootOwnsAtmosphere)
        XCTAssertTrue(MobileRegularBrowserBackdropPolicy.extendsBehindTopSafeArea)
        XCTAssertFalse(
            MobileBrowserSidebarBackdropPolicy.showsPageBackdrop(
                for: .regularSidebar,
                isPaging: false,
                isSelected: true
            )
        )
        XCTAssertTrue(
            MobileBrowserSidebarBackdropPolicy.showsPageBackdrop(
                for: .compactTabViewer,
                isPaging: false,
                isSelected: true
            )
        )
    }

    func testPrivateSpaceLockCentersAnUngroupedDetailSurface() {
        XCTAssertFalse(BrowserSpaceAccessLayout.usesGroupedActionCard)
        XCTAssertTrue(BrowserSpaceAccessLayout.centersContentOnBothAxes)
        XCTAssertGreaterThanOrEqual(BrowserSpaceAccessLayout.maximumContentWidth, 360)
        XCTAssertLessThanOrEqual(BrowserSpaceAccessLayout.maximumContentWidth, 520)
        XCTAssertFalse(BrowserSpaceAccessPresentation.contentOverlay.showsSpaceMenu)
    }

    func testLockedSpaceExitPreservesDockedAndFloatingSidebarModes() {
        XCTAssertEqual(
            MobileBrowserSpaceSwitchPolicy.destinationAfterLeavingLockedSpace(
                in: .compact,
                sidebarPresentation: .docked
            ),
            .tabViewer
        )
        XCTAssertEqual(
            MobileBrowserSpaceSwitchPolicy.destinationAfterLeavingLockedSpace(
                in: .compact,
                sidebarPresentation: .floating
            ),
            .selectedPage
        )
        XCTAssertEqual(
            MobileBrowserSpaceSwitchPolicy.destinationAfterLeavingLockedSpace(
                in: .regular,
                sidebarPresentation: .docked
            ),
            .selectedPage
        )
    }

    func testMobileSidebarKeepsFullBleedSpaceBackgroundsDuringPaging() throws {
        let session = BrowserSession.preview
        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.dropFirst().first)
        let settled = MobileBrowserSidebarBackdropPolicy.style(isPaging: false)
        let paging = MobileBrowserSidebarBackdropPolicy.style(isPaging: true)

        XCTAssertTrue(MobileBrowserSidebarBackdropPolicy.isFullBleed(isPaging: false))
        XCTAssertFalse(settled.usesSharedSelectedSpaceBackdrop)
        XCTAssertTrue(MobileBrowserSidebarBackdropPolicy.pagerOwnsFullSurface)
        XCTAssertTrue(MobileBrowserSidebarBackdropPolicy.pageBackdropIgnoresSafeArea)
        XCTAssertTrue(MobileBrowserSidebarBackdropPolicy.usesSingleBackdropLayer)
        XCTAssertFalse(MobileBrowserSidebarBackdropPolicy.requiresPagingStateUpdates)
        XCTAssertEqual(settled.horizontalInset, 0)
        XCTAssertEqual(settled.verticalInset, 0)
        XCTAssertEqual(settled.cornerRadius, 0)
        XCTAssertTrue(
            MobileBrowserSidebarBackdropPolicy.showsPageBackdrop(
                for: .compactTabViewer,
                isPaging: false,
                isSelected: true
            )
        )
        XCTAssertTrue(
            MobileBrowserSidebarBackdropPolicy.showsPageBackdrop(
                for: .compactTabViewer,
                isPaging: false,
                isSelected: false
            )
        )

        XCTAssertTrue(MobileBrowserSidebarBackdropPolicy.isFullBleed(isPaging: true))
        XCTAssertFalse(paging.usesSharedSelectedSpaceBackdrop)
        XCTAssertEqual(paging.horizontalInset, 0)
        XCTAssertEqual(paging.verticalInset, 0)
        XCTAssertEqual(paging.cornerRadius, 0)
        XCTAssertTrue(
            MobileBrowserSidebarBackdropPolicy.showsPageBackdrop(
                for: .compactTabViewer,
                isPaging: true,
                isSelected: true
            )
        )
        XCTAssertFalse(MobileBrowserSidebarBackdropPolicy.usesMatchedGeometryMorph)
        XCTAssertFalse(MobileBrowserSidebarBackdropPolicy.usesOpacityCrossfade)
        XCTAssertEqual(
            MobileBrowserSidebarBackdropPolicy.branding(for: work),
            work.branding
        )
        XCTAssertEqual(
            MobileBrowserSidebarBackdropPolicy.branding(for: personal),
            personal.branding
        )
    }

    func testMobilePageStartsWithItsPersistedFaviconCache() throws {
        let space = makeSpace(index: 76)
        var tab = try XCTUnwrap(space.tabs.first)
        tab.faviconData = Data([0x01, 0x02, 0x03])

        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )

        XCTAssertEqual(page.faviconData, tab.faviconData)
    }

    func testMobilePageCanRequestDesktopAndReturnToRecommendedContent() throws {
        let space = makeSpace(index: 75)
        let tab = try XCTUnwrap(space.tabs.first)
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )

        XCTAssertFalse(page.isRequestingDesktopSite)
        XCTAssertEqual(
            page.webView.configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended
        )

        page.togglePreferredContentMode()
        XCTAssertTrue(page.isRequestingDesktopSite)
        XCTAssertEqual(
            page.webView.configuration.defaultWebpagePreferences.preferredContentMode,
            .desktop
        )

        page.togglePreferredContentMode()
        XCTAssertFalse(page.isRequestingDesktopSite)
        XCTAssertEqual(
            page.webView.configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended
        )
    }

    func testPrivateMobilePagesUseDistinctEphemeralStoresAndNoCredentialBridge() throws {
        let browser = BrowserStore.privateBrowsing()
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )

        pages.select(session: browser.session)
        let firstPage = try XCTUnwrap(pages.activePage)
        let firstStore = firstPage.webView.configuration.websiteDataStore

        XCTAssertFalse(firstStore.isPersistent)
        XCTAssertNil(firstStore.identifier)
        let privateScripts = firstPage.webView.configuration.userContentController.userScripts
        XCTAssertTrue(privateScripts.contains { $0.source.contains("webkit-playsinline") })
        XCTAssertFalse(
            privateScripts.contains {
                $0.source.contains(BrowserCredentialContentBridge.messageHandlerName)
            }
        )

        browser.addSpace()
        pages.select(session: browser.session)
        let secondPage = try XCTUnwrap(pages.activePage)
        let secondStore = secondPage.webView.configuration.websiteDataStore

        XCTAssertEqual(browser.selectedSpace?.name, "Private 2")
        XCTAssertFalse(firstStore === secondStore)
        XCTAssertEqual(pages.residentPageCount, 2)

        pages.closePrivateBrowsingSession(browser.session)
        browser.resetPrivateBrowsingSession()

        XCTAssertEqual(pages.residentPageCount, 0)
        XCTAssertNil(pages.activePage)
        XCTAssertEqual(browser.selectedSpace?.name, "Private")
        XCTAssertEqual(browser.session.spaces.count, 1)
    }

    func testXCTestStandardMobilePagesNeverUseTheInstalledWebsiteDataStore() throws {
        let browser = BrowserStore.preview()
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )

        pages.select(session: browser.session)
        let store = try XCTUnwrap(
            pages.activePage?.webView.configuration.websiteDataStore
        )

        XCTAssertFalse(store.isPersistent)
        XCTAssertNil(store.identifier)
    }

    func testPrivateDownloadConfirmationStaysOwnedByThePrivateSpace() async throws {
        let standardPages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        let privatePages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let sourceURL = try XCTUnwrap(
            URL(string: "https://downloads.crest.test/private-tool.command")
        )
        let assessment = BrowserDownloadRiskAssessment(
            sanitizedFilename: "private-tool.command",
            reasons: [.executableOrInstaller]
        )

        let approval = Task {
            await privatePages.downloadRiskConfirmation.requestApproval(
                assessment: assessment,
                sourceURL: sourceURL,
                spaceName: "Private"
            )
        }
        try await waitUntil {
            privatePages.downloadRiskConfirmation.request != nil
        }

        XCTAssertFalse(
            standardPages.downloadRiskConfirmation
                === privatePages.downloadRiskConfirmation
        )
        XCTAssertNil(standardPages.downloadRiskConfirmation.request)
        XCTAssertEqual(
            privatePages.downloadRiskConfirmation.request?.assessment,
            assessment
        )
        XCTAssertEqual(
            privatePages.downloadRiskConfirmation.request?.spaceName,
            "Private"
        )
        XCTAssertEqual(
            privatePages.downloadRiskConfirmation.request?.sourceLabel,
            "downloads.crest.test"
        )
        XCTAssertTrue(
            privatePages.downloadRiskConfirmation.request?.message.contains(
                "This request belongs only to the Private Space."
            ) == true
        )

        privatePages.downloadRiskConfirmation.cancel()

        let wasApproved = await approval.value
        XCTAssertFalse(wasApproved)
        XCTAssertNil(privatePages.downloadRiskConfirmation.request)
    }

    func testDownloadConfirmationQueuesConcurrentRequestsWithoutChangingSpaceOwnership() async throws {
        let confirmation = MobileDownloadRiskConfirmationCoordinator()
        let firstAssessment = BrowserDownloadRiskAssessment(
            sanitizedFilename: "first.command",
            reasons: [.executableOrInstaller]
        )
        let secondAssessment = BrowserDownloadRiskAssessment(
            sanitizedFilename: "second.mobileconfig",
            reasons: [.executableOrInstaller, .dangerousTypeMismatch]
        )

        let firstApproval = Task {
            await confirmation.requestApproval(
                assessment: firstAssessment,
                sourceURL: URL(string: "https://first.crest.test/file"),
                spaceName: "Work"
            )
        }
        try await waitUntil {
            confirmation.request?.assessment == firstAssessment
        }
        let secondApproval = Task {
            await confirmation.requestApproval(
                assessment: secondAssessment,
                sourceURL: URL(string: "https://second.crest.test/file"),
                spaceName: "Private"
            )
        }
        await Task.yield()

        XCTAssertEqual(confirmation.request?.assessment, firstAssessment)
        XCTAssertEqual(confirmation.request?.spaceName, "Work")

        confirmation.approve()

        let firstWasApproved = await firstApproval.value
        XCTAssertTrue(firstWasApproved)
        try await waitUntil {
            confirmation.request?.assessment == secondAssessment
        }
        XCTAssertEqual(confirmation.request?.spaceName, "Private")

        confirmation.cancel()

        let secondWasApproved = await secondApproval.value
        XCTAssertFalse(secondWasApproved)
        XCTAssertNil(confirmation.request)
    }

    func testDismissingDownloadConfirmationFailsClosed() async throws {
        let confirmation = MobileDownloadRiskConfirmationCoordinator()
        let assessment = BrowserDownloadRiskAssessment(
            sanitizedFilename: "installer.pkg",
            reasons: [.executableOrInstaller]
        )
        let approval = Task {
            await confirmation.requestApproval(
                assessment: assessment,
                sourceURL: nil,
                spaceName: "Personal"
            )
        }
        try await waitUntil { confirmation.isPresented }

        confirmation.isPresented = false

        let wasApproved = await approval.value
        XCTAssertFalse(wasApproved)
        XCTAssertNil(confirmation.request)
    }

    func testCompactPresentationStartsWithTheFullScreenSidebar() {
        let navigation = MobileBrowserNavigationState()

        navigation.adapt(to: .compact)

        XCTAssertFalse(navigation.compactShowsPage)
        XCTAssertTrue(navigation.compactTabViewerChromeIsVisible)
        XCTAssertTrue(navigation.defersPageActivation)
        navigation.selectTab()
        XCTAssertTrue(navigation.compactShowsPage)
        XCTAssertFalse(navigation.compactPageIsFullyPresented)
        XCTAssertFalse(navigation.compactTabViewerChromeIsVisible)
        XCTAssertFalse(navigation.defersPageActivation)
        navigation.completePagePresentation()
        XCTAssertTrue(navigation.compactPageIsFullyPresented)
        navigation.showTabViewer()
        XCTAssertFalse(navigation.compactShowsPage)
        XCTAssertTrue(
            navigation.compactTabViewerChromeIsVisible,
            "The stable tab-view state and its actions must return in the same in-place morph transaction."
        )
        XCTAssertTrue(navigation.defersPageActivation)
    }

    func testColdLaunchCanActivateTheSelectedTabWithoutShowingTheTabViewer() {
        let navigation = MobileBrowserNavigationState(initiallyShowsCompactPage: true)

        navigation.adapt(to: .compact)

        XCTAssertTrue(navigation.compactShowsPage)
        XCTAssertTrue(navigation.compactPageIsFullyPresented)
        XCTAssertFalse(navigation.compactTabViewerChromeIsVisible)
        XCTAssertFalse(navigation.defersPageActivation)
    }

    func testDynamicMobilePageActionsRemainDeferredLocalizedResources() {
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        let readerTitle: LocalizedStringResource = pages.readerModeActionTitle
        let contentModeTitle: LocalizedStringResource = pages.preferredContentModeActionTitle

        XCTAssertEqual(String(localized: readerTitle), "Show Reader")
        XCTAssertEqual(String(localized: contentModeTitle), "Request Desktop Website")
    }

    func testCompactTabViewerKeepsItsChromeOutOfThePresentedPage() {
        XCTAssertFalse(MobileCompactTabViewerLayout.showsTopAddressBar)

        XCTAssertEqual(
            MobileBrowserSidebarBottomChromePolicy.placement(
                for: .compactTabViewer,
                isVisible: true
            ),
            .inlineSafeAreaInset,
            "iPhone Space actions must stay inside the tab-view hierarchy, not in a persistent system bar."
        )
        XCTAssertEqual(
            MobileBrowserSidebarBottomChromePolicy.placement(
                for: .compactTabViewer,
                isVisible: false
            ),
            .inlineSafeAreaInset,
            "The hidden tab-page actions must keep their inset reserved so the matched tab destination never moves during the page morph."
        )
        XCTAssertEqual(
            MobileBrowserSidebarBottomChromePolicy.content(
                for: .compactTabViewer,
                isVisible: true
            ),
            .actions
        )
        XCTAssertEqual(
            MobileBrowserSidebarBottomChromePolicy.content(
                for: .compactTabViewer,
                isVisible: false
            ),
            .reservedSpace,
            "The page cover must retain the viewer's resting geometry without exposing Private, Archive, or Settings controls."
        )
        XCTAssertEqual(
            MobileBrowserSidebarBottomChromePolicy.placement(
                for: .regularSidebar,
                isVisible: true
            ),
            .inlineSafeAreaInset,
            "iPad Space actions must not create a window-wide bottom safe-area bar."
        )
    }

    @MainActor
    func testMobileArchiveAndDownloadsPresentationIsWindowOwned() {
        let firstWindow = MobileBrowserNavigationState()
        let secondWindow = MobileBrowserNavigationState()

        firstWindow.utilityPresentation.present(.archive)

        XCTAssertEqual(firstWindow.utilityPresentation.surface, .archive)
        XCTAssertNil(secondWindow.utilityPresentation.surface)

        firstWindow.utilityPresentation.present(.downloads)

        XCTAssertEqual(firstWindow.utilityPresentation.surface, .downloads)
        XCTAssertNil(secondWindow.utilityPresentation.surface)

        firstWindow.utilityPresentation.dismiss(.archive)
        XCTAssertEqual(firstWindow.utilityPresentation.surface, .downloads)

        firstWindow.utilityPresentation.dismiss(.downloads)
        XCTAssertNil(firstWindow.utilityPresentation.surface)
    }

    func testCompactTabViewerDismissesDirectlyToItsStableMatchedSource() {
        let navigation = MobileBrowserNavigationState()

        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()
        navigation.dismissPageToTabViewer()

        XCTAssertFalse(navigation.compactShowsPage)
        XCTAssertTrue(navigation.compactTabViewerChromeIsVisible)
    }

    func testCompactPagePrepositionsOnlySourcesThatChangeBehindThePresentedPage() throws {
        let firstTab = BrowserTab(
            title: "First",
            url: URL(string: "https://example.com/first"),
            placement: .current
        )
        let promotedDraft = BrowserTab(
            title: "Promoted draft",
            url: URL(string: "https://example.com/promoted"),
            placement: .current
        )

        let firstTarget = try XCTUnwrap(
            MobileTabPromotionPolicy.target(
                for: firstTab,
                selectedTabID: firstTab.id
            )
        )
        let promotedTarget = try XCTUnwrap(
            MobileTabPromotionPolicy.target(
                for: promotedDraft,
                selectedTabID: promotedDraft.id
            )
        )

        XCTAssertFalse(
            MobileTabPromotionPolicy.shouldPreposition(
                previous: nil,
                current: firstTarget,
                compactPageIsFullyPresented: false
            ),
            "A tab tapped in the visible viewer must remain at its tapped source frame while the cover presents."
        )
        XCTAssertTrue(
            MobileTabPromotionPolicy.shouldPreposition(
                previous: nil,
                current: promotedTarget,
                compactPageIsFullyPresented: true
            ),
            "A Start Page that becomes a real tab behind the cover needs a stable onscreen dismissal target."
        )
        XCTAssertTrue(
            MobileTabPromotionPolicy.shouldPreposition(
                previous: firstTarget,
                current: promotedTarget,
                compactPageIsFullyPresented: true
            )
        )
        XCTAssertFalse(
            MobileTabPromotionPolicy.shouldPreposition(
                previous: promotedTarget,
                current: promotedTarget,
                compactPageIsFullyPresented: true
            )
        )
    }

    func testCompactPageMorphTargetsPinnedSavedAndCurrentTabs() {
        let selectedTab = BrowserTab(
            title: "Selected",
            url: URL(string: "https://example.com/selected"),
            placement: .current
        )
        let otherTab = BrowserTab(
            title: "Other",
            url: URL(string: "https://example.com/other"),
            placement: .current
        )
        let startPage = BrowserTab.startPage()

        XCTAssertTrue(
            MobileTabPromotionPolicy.usesNativeNavigationTransition,
            "The page must use the matched full-screen-cover transition lifecycle."
        )

        for placement in [TabPlacement.pinned, .saved, .current] {
            XCTAssertTrue(MobileTabPromotionPolicy.supports(placement))
            XCTAssertEqual(
                MobileTabPromotionPolicy.destinationID(for: selectedTab.id),
                "crest-tab-promotion-\(selectedTab.id)"
            )
        }

        XCTAssertTrue(
            MobileTabPromotionPolicy.isTransitionSource(
                selectedTab,
                selectedTabID: selectedTab.id
            )
        )
        XCTAssertFalse(
            MobileTabPromotionPolicy.isTransitionSource(
                otherTab,
                selectedTabID: selectedTab.id
            ),
            "Crest must expose only the selected tab as the stable transition source."
        )
        XCTAssertFalse(
            MobileTabPromotionPolicy.isTransitionSource(
                startPage,
                selectedTabID: startPage.id
            ),
            "The Start Page is a draft view, not a tab destination."
        )
    }

    func testExplicitSessionResetAlsoIsolatesPerWindowSelectionState() {
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(
                    values: ["CREST_RESET_SESSION": "1"],
                    isXCTestRuntime: false
                )
            ),
            "An isolated reset must not restore stale per-window selection state."
        )
        XCTAssertTrue(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(values: [:], isXCTestRuntime: true)
            )
        )
        XCTAssertFalse(
            BrowserLaunchIsolationPolicy.requiresIsolation(
                BrowserLaunchEnvironment(values: [:], isXCTestRuntime: false)
            )
        )
    }

    func testRegularPresentationDoesNotMutateTheCompactNavigationChoice() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()

        navigation.adapt(to: .regular)
        XCTAssertFalse(navigation.defersPageActivation)
        navigation.adapt(to: .compact)

        XCTAssertTrue(navigation.compactShowsPage)
        XCTAssertFalse(navigation.defersPageActivation)
    }

    func testOnlyExpandedContainersUseTheRegularBrowserPresentation() {
        XCTAssertEqual(
            MobileBrowserPresentationPolicy.resolve(
                availableWidth: 430
            ),
            .compact
        )
        XCTAssertEqual(
            MobileBrowserPresentationPolicy.resolve(
                availableWidth: 852
            ),
            .regular
        )
        XCTAssertEqual(
            MobileBrowserPresentationPolicy.resolve(
                availableWidth: 599
            ),
            .compact,
            "A setting must not force a thin phone into the expanded shell."
        )
    }

    func testCompactSidebarUsesItsFullScreenViewerAsTheDockedState() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)

        XCTAssertEqual(navigation.compactSidebarPresentation, .docked)
        XCTAssertFalse(navigation.compactShowsPage)

        navigation.toggleCompactSidebar()
        XCTAssertEqual(navigation.compactSidebarPresentation, .floating)
        XCTAssertTrue(navigation.compactShowsPage)

        navigation.toggleCompactSidebar()
        XCTAssertEqual(navigation.compactSidebarPresentation, .docked)
        XCTAssertFalse(navigation.compactShowsPage)

        navigation.selectTab()
        XCTAssertEqual(navigation.compactSidebarPresentation, .collapsed)
        XCTAssertTrue(navigation.compactShowsPage)
    }

    func testSelectingFromTheFullScreenPhoneSidebarUsesTheDockedDetailFlow() {
        let navigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: false
        )
        navigation.adapt(to: .compact)

        XCTAssertEqual(navigation.compactSidebarPresentation, .docked)
        XCTAssertFalse(navigation.regularSidebarIsDocked)

        navigation.selectTab()

        XCTAssertTrue(navigation.regularSidebarIsDocked)
        XCTAssertTrue(navigation.compactShowsPage)
    }

    func testCollapsedSidebarFullscreenOnlyChangesTheFloatingSinglePageFrame() {
        XCTAssertFalse(
            MobileSidebarPageFramePolicy.usesBorderlessFrame(
                preferenceIsEnabled: false,
                sidebarPresentation: .floating,
                presentsSplitView: false,
                browserPresentation: .compact
            )
        )
        XCTAssertTrue(
            MobileSidebarPageFramePolicy.usesBorderlessFrame(
                preferenceIsEnabled: true,
                sidebarPresentation: .collapsed,
                presentsSplitView: false,
                browserPresentation: .compact
            )
        )
        XCTAssertTrue(
            MobileSidebarPageFramePolicy.usesBorderlessFrame(
                preferenceIsEnabled: true,
                sidebarPresentation: .floating,
                presentsSplitView: false,
                browserPresentation: .regular
            )
        )
        XCTAssertTrue(
            MobileSidebarPageFramePolicy.usesBorderlessFrame(
                preferenceIsEnabled: false,
                sidebarPresentation: .docked,
                presentsSplitView: false,
                browserPresentation: .compact
            ),
            "The docked phone's tab-to-detail transition remains the existing borderless presentation."
        )
        XCTAssertFalse(
            MobileSidebarPageFramePolicy.usesBorderlessFrame(
                preferenceIsEnabled: true,
                sidebarPresentation: .docked,
                presentsSplitView: false,
                browserPresentation: .regular
            )
        )
        XCTAssertFalse(
            MobileSidebarPageFramePolicy.usesBorderlessFrame(
                preferenceIsEnabled: true,
                sidebarPresentation: .floating,
                presentsSplitView: true,
                browserPresentation: .compact
            )
        )
    }

    func testOnlyDockedPhoneDetailsAndSplitViewKeepTheCompactToolbar() {
        XCTAssertTrue(
            MobileSidebarPageFramePolicy.showsCompactToolbar(
                sidebarPresentation: .docked,
                presentsSplitView: false
            )
        )
        XCTAssertFalse(
            MobileSidebarPageFramePolicy.showsCompactToolbar(
                sidebarPresentation: .floating,
                presentsSplitView: false
            )
        )
        XCTAssertFalse(
            MobileSidebarPageFramePolicy.showsCompactToolbar(
                sidebarPresentation: .collapsed,
                presentsSplitView: false
            )
        )
        XCTAssertTrue(
            MobileSidebarPageFramePolicy.showsCompactToolbar(
                sidebarPresentation: .floating,
                presentsSplitView: true
            ),
            "Split View keeps the floating toolbar because it owns the card-swipe interaction."
        )
    }

    func testSelectingATabDismissesOnlyTheFloatingPhoneSidebar() {
        XCTAssertTrue(
            MobileSidebarTabSelectionPolicy.dismissesSidebar(
                browserPresentation: .compact,
                sidebarPresentation: .floating
            )
        )
        XCTAssertFalse(
            MobileSidebarTabSelectionPolicy.dismissesSidebar(
                browserPresentation: .compact,
                sidebarPresentation: .docked
            )
        )
        XCTAssertFalse(
            MobileSidebarTabSelectionPolicy.dismissesSidebar(
                browserPresentation: .regular,
                sidebarPresentation: .floating
            ),
            "iPad keeps the normal shared floating-sidebar selection behavior."
        )
    }

    func testWebContentKeepsNativeBackNavigationOutsideTheRevealStrip() throws {
        let space = makeSpace(index: 66)
        let page = MobileBrowserPage(
            tab: try XCTUnwrap(space.tabs.first),
            space: space,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )

        XCTAssertTrue(page.webView.allowsBackForwardNavigationGestures)
        XCTAssertEqual(
            MobileBrowserChromeLayout.collapsedSidebarRevealWidth,
            26,
            "Only the extreme leading edge is reserved for revealing the sidebar; the rest of the page remains WebKit navigation territory."
        )
    }

    func testOnlyFloatingKeyboardsIgnoreTheKeyboardSafeArea() {
        let availableSize = CGSize(width: 1_366, height: 1_024)

        XCTAssertFalse(
            MobileKeyboardLayoutPolicy.isFloating(
                keyboardFrame: CGRect(x: 0, y: 650, width: 1_366, height: 374),
                availableSize: availableSize
            )
        )
        XCTAssertTrue(
            MobileKeyboardLayoutPolicy.isFloating(
                keyboardFrame: CGRect(x: 930, y: 610, width: 360, height: 280),
                availableSize: availableSize
            )
        )
        XCTAssertFalse(
            MobileKeyboardLayoutPolicy.isFloating(
                keyboardFrame: .null,
                availableSize: availableSize
            )
        )

        let resizedPhoneWindow = CGSize(width: 701, height: 435)
        XCTAssertTrue(
            MobileKeyboardLayoutPolicy.isFloating(
                keyboardFrame: CGRect(x: 260, y: 253, width: 270, height: 182),
                availableSize: resizedPhoneWindow
            ),
            "Floating-keyboard handling must be based on the window, not the device family."
        )
        XCTAssertFalse(
            MobileKeyboardLayoutPolicy.isFloating(
                keyboardFrame: CGRect(x: 0, y: 150, width: 701, height: 285),
                availableSize: resizedPhoneWindow
            )
        )
    }

    func testRegularSidebarPresentationRestoresPerNativeWindow() {
        let hiddenWindow = MobileBrowserNavigationState(
            regularSidebarIsPresented: false
        )
        let visibleWindow = MobileBrowserNavigationState(
            regularSidebarIsPresented: true
        )

        XCTAssertFalse(hiddenWindow.regularSidebarIsPresented)
        XCTAssertTrue(visibleWindow.regularSidebarIsPresented)
    }

    func testRegularWindowLayoutProtectsPageWidthAndUsesAnOverlayBelowItsMinimum() {
        XCTAssertEqual(
            MobileRegularWindowLayoutPolicy.resolve(
                availableWidth: 1_366,
                preferredSidebarWidth: 360
            ),
            .sideBySide(sidebarWidth: 360)
        )
        XCTAssertEqual(
            MobileRegularWindowLayoutPolicy.resolve(
                availableWidth: 600,
                preferredSidebarWidth: 380
            ),
            .sideBySide(sidebarWidth: 280)
        )
        XCTAssertEqual(
            MobileRegularWindowLayoutPolicy.resolve(
                availableWidth: 579,
                preferredSidebarWidth: 320
            ),
            .overlay(sidebarWidth: 320)
        )
        XCTAssertEqual(
            MobileRegularWindowLayoutPolicy.resolve(
                availableWidth: 320,
                preferredSidebarWidth: 320
            ),
            .overlay(sidebarWidth: 276)
        )
    }

    func testRegularPageFrameOnlyAdjoinsASideBySideSidebar() {
        XCTAssertTrue(
            MobileRegularWindowLayout.sideBySide(sidebarWidth: 320)
                .reservesSidebarWidth
        )
        XCTAssertFalse(
            MobileRegularWindowLayout.overlay(sidebarWidth: 320)
                .reservesSidebarWidth
        )
    }

    func testEverySupportedStageManagerWidthPreservesEitherAUsablePageOrAnExposedPageEdge() {
        let preferredWidths: [CGFloat] = [
            BrowserChromeLayout.sidebarMinimumWidth,
            BrowserChromeLayout.sidebarIdealWidth,
            BrowserChromeLayout.sidebarMaximumWidth,
        ]

        for availableWidth in 320...1_366 {
            for preferredSidebarWidth in preferredWidths {
                let layout = MobileRegularWindowLayoutPolicy.resolve(
                    availableWidth: CGFloat(availableWidth),
                    preferredSidebarWidth: preferredSidebarWidth
                )

                switch layout {
                case .sideBySide(let sidebarWidth):
                    XCTAssertGreaterThanOrEqual(
                        CGFloat(availableWidth) - sidebarWidth,
                        MobileRegularWindowLayoutPolicy.minimumDetailWidth
                    )
                    XCTAssertGreaterThanOrEqual(
                        sidebarWidth,
                        BrowserChromeLayout.sidebarMinimumWidth
                    )
                    XCTAssertLessThanOrEqual(sidebarWidth, preferredSidebarWidth)
                case .overlay(let sidebarWidth):
                    XCTAssertGreaterThanOrEqual(
                        CGFloat(availableWidth) - sidebarWidth,
                        MobileRegularWindowLayoutPolicy.overlayEdgeClearance
                    )
                    XCTAssertLessThanOrEqual(sidebarWidth, preferredSidebarWidth)
                }
            }
        }
    }

    func testRegularSidebarVisibilitySurvivesStageManagerLayoutTransitions() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .regular)

        XCTAssertTrue(navigation.regularSidebarIsPresented)

        navigation.hideRegularSidebar()
        XCTAssertFalse(navigation.regularSidebarIsPresented)
        XCTAssertEqual(navigation.regularSidebarPresentation, .collapsed)

        navigation.showRegularSidebar()
        XCTAssertTrue(navigation.regularSidebarIsPresented)
        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)

        navigation.toggleRegularSidebar()
        XCTAssertTrue(navigation.regularSidebarIsPresented)
        XCTAssertTrue(navigation.regularSidebarIsDocked)
        navigation.toggleRegularSidebar()
        XCTAssertFalse(navigation.regularSidebarIsPresented)
        navigation.toggleRegularSidebar()
        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)
    }

    func testTransientRegularSidebarDismissesAfterItsIdleDelay() async {
        let navigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: false,
            transientSidebarDismissalDelay: .milliseconds(20)
        )

        navigation.showRegularSidebar()
        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)

        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(navigation.regularSidebarPresentation, .collapsed)
    }

    func testTransientRegularSidebarPausesWhileATabIsBeingDragged() async {
        let navigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: false,
            transientSidebarDismissalDelay: .milliseconds(20)
        )

        navigation.showRegularSidebar()
        navigation.setTransientSidebarDismissalPaused(true)
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)

        navigation.setTransientSidebarDismissalPaused(false)
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(navigation.regularSidebarPresentation, .collapsed)
    }

    func testMobileBrowserCommandControllerCyclesTabsAndSpaces() throws {
        let tabs = (1...3).map { index in
            BrowserTab(
                id: TabID(rawValue: fixedUUID(500 + index)),
                title: "Tab \(index)",
                url: nil,
                symbol: "globe",
                placement: .current
            )
        }
        let firstSpace = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(510)),
            profile: BrowsingProfile(id: fixedUUID(511)),
            name: "Commands",
            symbol: "keyboard",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs[0].id
        )
        let secondSpace = makeSpace(index: 52)
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [firstSpace, secondSpace],
                selectedSpaceID: firstSpace.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        let commands = MobileBrowserCommandController(browser: browser, pages: pages)
        pages.select(session: browser.session)

        XCTAssertEqual(commands.selectNextTab(), tabs[1].id)
        XCTAssertEqual(browser.selectedTab?.id, tabs[1].id)
        XCTAssertEqual(pages.activePage?.tabID, tabs[1].id)
        XCTAssertEqual(commands.selectPreviousTab(), tabs[0].id)
        XCTAssertEqual(commands.selectPreviousTab(), tabs[2].id)

        XCTAssertEqual(commands.selectNextSpace(), secondSpace.id)
        XCTAssertEqual(browser.selectedSpace?.id, secondSpace.id)
        XCTAssertEqual(pages.activePage?.spaceID, secondSpace.id)
        XCTAssertEqual(commands.selectPreviousSpace(), firstSpace.id)
    }

    func testMobileBrowserCommandControllerArchivesAndReopensTheSelectedTab() throws {
        let first = BrowserTab(
            title: "First",
            url: URL(string: "https://example.com/first"),
            placement: .current
        )
        let second = BrowserTab(
            title: "Second",
            url: URL(string: "https://example.com/second"),
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(530)),
            profile: BrowsingProfile(id: fixedUUID(531)),
            name: "Commands",
            symbol: "keyboard",
            accent: .teal,
            folders: [],
            tabs: [first, second],
            selectedTabID: first.id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        let commands = MobileBrowserCommandController(browser: browser, pages: pages)
        browser.selectTab(second.id)
        pages.select(session: browser.session)

        XCTAssertEqual(commands.archiveSelectedTab(), second.id)
        XCTAssertEqual(browser.selectedSpace?.archivedTabs.map(\.id), [second.id])
        XCTAssertEqual(pages.activePage?.tabID, first.id)

        XCTAssertEqual(commands.reopenClosedTab(), second.id)
        XCTAssertEqual(browser.selectedTab?.id, second.id)
        XCTAssertEqual(pages.activePage?.tabID, second.id)
    }

    func testMobileBrowserCommandControllerUnloadsPinnedTabWithoutRemovingIt() {
        let previous = BrowserTab(
            title: "Previous",
            url: URL(string: "https://example.com/previous"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 100)
        )
        let pinned = BrowserTab(
            title: "Pinned",
            url: URL(string: "https://example.com/pinned"),
            placement: .pinned,
            lastActivatedAt: Date(timeIntervalSince1970: 110)
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(532)),
            profile: BrowsingProfile(id: fixedUUID(533)),
            name: "Commands",
            symbol: "keyboard",
            accent: .teal,
            folders: [],
            tabs: [pinned, previous],
            selectedTabID: pinned.id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        let commands = MobileBrowserCommandController(browser: browser, pages: pages)
        browser.selectTab(previous.id)
        browser.selectTab(pinned.id)
        pages.select(session: browser.session)

        XCTAssertTrue(pages.containsResidentPage(for: pinned.id))
        XCTAssertEqual(commands.dismissSelectedTab(), pinned.id)

        XCTAssertTrue(browser.selectedSpace?.contains(pinned.id) == true)
        XCTAssertTrue(browser.selectedSpace?.archivedTabs.isEmpty == true)
        XCTAssertEqual(browser.selectedTab?.id, previous.id)
        XCTAssertFalse(pages.containsResidentPage(for: pinned.id))
        XCTAssertTrue(pages.containsResidentPage(for: previous.id))
    }

    func testMobileBrowserCommandControllerDuplicatesTheSelectedTabAndSynchronizesItsPage() throws {
        let source = BrowserTab(
            title: "Reference",
            url: try XCTUnwrap(URL(string: "https://example.com/reference")),
            placement: .saved
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [source],
            selectedTabID: source.id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        pages.select(session: browser.session)
        let commands = MobileBrowserCommandController(browser: browser, pages: pages)

        let duplicateID = try XCTUnwrap(commands.duplicateSelectedTab())

        XCTAssertEqual(browser.selectedTab?.id, duplicateID)
        XCTAssertEqual(browser.selectedTab?.placement, .current)
        XCTAssertEqual(browser.selectedTab?.url, source.url)
        XCTAssertEqual(pages.activePage?.tabID, duplicateID)
        XCTAssertEqual(pages.activePage?.profileID, space.profile.id)
    }

    func testPinnedGridRetainsTheMeasuredArcColumnCounts() {
        let expected = [1, 2, 3, 4, 3, 3, 4, 4, 3, 4, 4, 4]

        XCTAssertEqual(
            (1...12).map(PinnedTabGridLayout.columnCount(for:)),
            expected
        )
    }

    func testSpaceSwipePolicyRequiresADeliberateHorizontalGesture() {
        XCTAssertEqual(
            BrowserSpaceSwipePolicy.direction(for: CGSize(width: -90, height: 12)),
            .next
        )
        XCTAssertEqual(
            BrowserSpaceSwipePolicy.direction(for: CGSize(width: 90, height: -8)),
            .previous
        )
        XCTAssertNil(BrowserSpaceSwipePolicy.direction(for: CGSize(width: 60, height: 0)))
        XCTAssertNil(BrowserSpaceSwipePolicy.direction(for: CGSize(width: 80, height: 100)))
    }

    func testMobileInsertionTargetsDoNotOverlapRowsOrTheScrollBackground() {
        XCTAssertFalse(MobileSidebarDropTargetPolicy.acceptsDropsOnScrollBackground)
        XCTAssertTrue(MobileSidebarDropTargetPolicy.usesDedicatedSectionEndTargets)
        XCTAssertGreaterThanOrEqual(
            MobileSidebarDropTargetPolicy.sectionEndTargetHeight,
            22
        )
    }

    func testRootFoldersAlignWithRootSavedTabs() {
        XCTAssertEqual(
            BrowserSavedFolderLayout.headerLeadingInset(
                depth: 0,
                tabRowMetrics: .touch
            ),
            BrowserSidebarTabRowMetrics.touch.contentLeadingInset
        )
        XCTAssertEqual(
            BrowserSavedFolderLayout.headerLeadingInset(
                depth: 1,
                tabRowMetrics: .touch
            ),
            BrowserSidebarTabRowMetrics.touch.contentLeadingInset
                + BrowserSavedFolderLayout.nestingIndent
        )
    }

    /// A folder's own rows step in one indent past the folder, and a nested
    /// folder's header lands in the same column as the rows above it.
    func testFolderRowsStepInOneIndentPastTheirFolder() {
        XCTAssertEqual(
            BrowserSavedFolderLayout.rowLeadingInset(depth: 0),
            BrowserSavedFolderLayout.nestingIndent
        )
        XCTAssertEqual(
            BrowserSavedFolderLayout.rowLeadingInset(depth: 1),
            BrowserSavedFolderLayout.nestingIndent * 2
        )
    }

    func testSplitGroupRowsKeepAStandardSmallGutterBetweenSurfaces() {
        XCTAssertEqual(
            BrowserSidebarSplitGroupRowMetrics.touch.rowVerticalInset * 2,
            CrestSpacing.extraSmall
        )
    }

    func testMobileLeadingChromeMirrorsForRightToLeftLayout() {
        XCTAssertEqual(
            BrowserChromeDirectionPolicy.leadingOffset(
                312,
                layoutDirection: .rightToLeft
            ),
            -312
        )
        XCTAssertTrue(
            BrowserChromeDirectionPolicy.isLeadingEdgeReveal(
                CGSize(width: -60, height: 4),
                layoutDirection: .rightToLeft
            )
        )
        XCTAssertEqual(
            BrowserSpaceSwipePolicy.direction(
                for: CGSize(width: 90, height: 4),
                layoutDirection: .rightToLeft
            ),
            .next
        )
    }

    func testCompactChromeGestureRequiresDominantExpectedDirection() {
        XCTAssertEqual(
            MobileCompactChromeTransitionPolicy.constrainedTranslation(
                CGSize(width: 4, height: -90),
                for: .revealTabViewer
            ),
            -90
        )
        XCTAssertEqual(
            MobileCompactChromeTransitionPolicy.constrainedTranslation(
                CGSize(width: 4, height: 90),
                for: .revealTabViewer
            ),
            0
        )
        XCTAssertEqual(
            MobileCompactChromeTransitionPolicy.constrainedTranslation(
                CGSize(width: 90, height: 40),
                for: .revealPage
            ),
            0
        )
    }

    func testCompactChromeGestureCommitsAtConfiguredThreshold() {
        XCTAssertTrue(
            MobileCompactChromeTransitionPolicy.commits(
                predictedEndTranslation: CGSize(width: 3, height: -64),
                for: .revealTabViewer
            )
        )
        XCTAssertTrue(
            MobileCompactChromeTransitionPolicy.commits(
                predictedEndTranslation: CGSize(width: 3, height: 64),
                for: .revealPage
            )
        )
        XCTAssertFalse(
            MobileCompactChromeTransitionPolicy.commits(
                predictedEndTranslation: CGSize(width: 3, height: 63),
                for: .revealPage
            )
        )
    }

    func testFullTabReservesPullDownForWebRefresh() throws {
        XCTAssertFalse(MobileFullTabPresentationPolicy.allowsInteractiveDismissal)

        let space = makeSpace(index: 46)
        let tab = try XCTUnwrap(space.tabs.first)
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )
        let refreshControl = try XCTUnwrap(page.webView.scrollView.refreshControl)

        XCTAssertTrue(refreshControl.allControlEvents.contains(.valueChanged))
        XCTAssertNotNil(
            refreshControl.actions(
                forTarget: page,
                forControlEvent: .valueChanged
            )
        )
    }

    func testAddressAndSearchFieldsUseTheStandardKeyboardWithASpaceBar() {
        XCTAssertEqual(BrowserAddressKeyboardPolicy.keyboardType, .default)
    }

    func testMobileMediaRequiresUserIntentStaysInlineAndAllowsSystemPictureInPicture() throws {
        let space = makeSpace(index: 45)
        let tab = try XCTUnwrap(space.tabs.first)
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )
        let configuration = page.webView.configuration

        XCTAssertTrue(configuration.allowsInlineMediaPlayback)
        XCTAssertTrue(configuration.allowsPictureInPictureMediaPlayback)
        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .all)
        XCTAssertTrue(
            configuration.userContentController.userScripts.contains {
                $0.source.contains("webkit-playsinline")
            }
        )
    }

    func testMobileHostDeclaresBackgroundModesForPictureInPictureAndCloudSync() throws {
        let backgroundModes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        )

        XCTAssertEqual(Set(backgroundModes), ["audio", "remote-notification"])
    }

    func testCompactWebFrameExtendsBehindTheToolbarWhileReportingItsObscuredArea() {
        let safeAreaInsets = UIEdgeInsets(top: 59, left: 7, bottom: 34, right: 9)
        let frameInsets = MobileBrowserViewportPolicy.webViewFrameInsets(
            safeAreaInsets: safeAreaInsets,
            bottomChromeHeight: MobileBrowserViewportPolicy.compactToolbarHeight
        )
        let overlayInsets = MobileBrowserViewportPolicy.chromeOverlayInsets(
            safeAreaInsets: safeAreaInsets,
            bottomChromeHeight: MobileBrowserViewportPolicy.compactToolbarHeight
        )

        XCTAssertEqual(frameInsets.top, 59)
        XCTAssertEqual(frameInsets.bottom, 0)
        XCTAssertEqual(frameInsets.left, 7)
        XCTAssertEqual(frameInsets.right, 9)
        XCTAssertEqual(overlayInsets.top, 0)
        XCTAssertEqual(overlayInsets.bottom, 90)
        XCTAssertEqual(overlayInsets.left, 0)
        XCTAssertEqual(overlayInsets.right, 0)

        let viewportRange = MobileBrowserViewportPolicy.viewportRangeInsets(
            safeAreaInsets: safeAreaInsets
        )
        XCTAssertEqual(viewportRange.minimum.bottom, 78)
        XCTAssertEqual(viewportRange.maximum.bottom, 90)
        XCTAssertEqual(viewportRange.minimum.top, 0)
        XCTAssertEqual(viewportRange.maximum.top, 0)
    }

    func testResolvedSafeAreaFollowsTheReadingDirectionIntoWebKitsGeometry() {
        let insets = EdgeInsets(top: 59, leading: 7, bottom: 34, trailing: 9)

        let leftToRight = MobileBrowserViewportPolicy.systemSafeAreaInsets(
            insets,
            layoutDirection: .leftToRight
        )
        let rightToLeft = MobileBrowserViewportPolicy.systemSafeAreaInsets(
            insets,
            layoutDirection: .rightToLeft
        )

        XCTAssertEqual(leftToRight.top, 59)
        XCTAssertEqual(leftToRight.bottom, 34)
        XCTAssertEqual(leftToRight.left, 7)
        XCTAssertEqual(leftToRight.right, 9)
        XCTAssertEqual(rightToLeft.top, 59)
        XCTAssertEqual(rightToLeft.bottom, 34)
        XCTAssertEqual(
            rightToLeft.left,
            9,
            "A right-to-left layout puts the trailing inset on the left."
        )
        XCTAssertEqual(rightToLeft.right, 7)
    }

    func testTheInlineViewportLeavesEveryInsetToTheContainer() {
        XCTAssertFalse(MobileBrowserPageViewport.inline.obscuresSystemSafeAreas)
        XCTAssertEqual(
            MobileBrowserPageViewport.inline.systemSafeAreaInsets,
            .zero
        )
        XCTAssertEqual(MobileBrowserPageViewport.inline.bottomChromeHeight, 0)
    }

    func testCompactWebHostKeepsScrollingContentFullHeightForExpandedAndCollapsedToolbars() throws {
        let space = makeSpace(index: 46)
        let tab = try XCTUnwrap(space.tabs.first)
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )
        let host = MobileBrowserWebHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let safeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

        host.configureViewport(
            MobileBrowserPageViewport(
                obscuresSystemSafeAreas: true,
                systemSafeAreaInsets: safeAreaInsets,
                bottomChromeHeight: MobileBrowserViewportPolicy.compactToolbarHeight
            )
        )
        host.attach(page.webView)
        host.layoutIfNeeded()

        let expectedObscuredBottom =
            safeAreaInsets.bottom
            + MobileBrowserViewportPolicy.compactToolbarHeight
        XCTAssertEqual(page.webView.scrollView.contentInset.top, 0)
        XCTAssertEqual(page.webView.scrollView.contentInset.left, 0)
        XCTAssertEqual(page.webView.scrollView.contentInset.right, 0)
        XCTAssertEqual(
            page.webView.scrollView.contentInset.bottom,
            expectedObscuredBottom,
            "Only the terminal scroll range should grow enough to lift the final page content above Crest's floating controls."
        )
        XCTAssertEqual(
            page.webView.scrollView.verticalScrollIndicatorInsets.bottom,
            expectedObscuredBottom
        )
        XCTAssertEqual(
            page.webView.obscuredContentInsets.bottom,
            expectedObscuredBottom,
            "Fixed and sticky content should avoid Crest's floating controls."
        )
        XCTAssertEqual(
            page.webView.minimumViewportInset.bottom,
            safeAreaInsets.bottom
                + MobileBrowserViewportPolicy.compactDomainChipHeight
        )
        XCTAssertEqual(
            page.webView.maximumViewportInset.bottom,
            expectedObscuredBottom
        )
        XCTAssertEqual(
            page.webView.frame.minY,
            host.bounds.minY + safeAreaInsets.top,
            "The status bar's rows belong to the host, not to the page."
        )
        XCTAssertEqual(page.webView.frame.maxY, host.bounds.maxY)

        host.configureViewport(
            MobileBrowserPageViewport(
                obscuresSystemSafeAreas: true,
                systemSafeAreaInsets: safeAreaInsets,
                bottomChromeHeight: MobileBrowserViewportPolicy.compactDomainChipHeight
            )
        )
        host.layoutIfNeeded()

        let expectedCollapsedBottom =
            safeAreaInsets.bottom
            + MobileBrowserViewportPolicy.compactDomainChipHeight
        XCTAssertEqual(
            page.webView.scrollView.contentInset.bottom,
            expectedCollapsedBottom,
            "The collapsed domain chip should leave its own smaller terminal scroll allowance."
        )
        XCTAssertEqual(
            page.webView.obscuredContentInsets.bottom,
            expectedCollapsedBottom
        )
        XCTAssertEqual(
            page.webView.minimumViewportInset.bottom,
            expectedCollapsedBottom
        )
        XCTAssertEqual(
            page.webView.maximumViewportInset.bottom,
            expectedObscuredBottom,
            "Collapsing the toolbar must not change WebKit's explicit viewport range."
        )
        XCTAssertEqual(
            page.webView.frame.minY,
            host.bounds.minY + safeAreaInsets.top
        )
        XCTAssertEqual(page.webView.frame.maxY, host.bounds.maxY)
    }

    /// The carousel lays its cells out inside a `ScrollView`, which resolves
    /// their safe area to zero. One shared viewport value is what keeps a card's
    /// web content on the same row as the single page's regardless.
    func testSplitCardCellsAbsorbTheSameTopSafeAreaAsTheSinglePage() throws {
        let safeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let viewport = MobileBrowserPageViewport(
            obscuresSystemSafeAreas: true,
            systemSafeAreaInsets: safeAreaInsets,
            bottomChromeHeight: MobileBrowserViewportPolicy.compactToolbarHeight
        )
        let singleSpace = makeSpace(index: 47)
        let cardSpace = makeSpace(index: 48)
        let singlePage = MobileBrowserPage(
            tab: try XCTUnwrap(singleSpace.tabs.first),
            space: singleSpace,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )
        let cardPage = MobileBrowserPage(
            tab: try XCTUnwrap(cardSpace.tabs.first),
            space: cardSpace,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )

        let singleWindow = mountBrowserSurface(
            safeAreaInsets: safeAreaInsets,
            content: MobileBrowserLivePageView(
                page: singlePage,
                viewport: viewport
            )
        )
        let carouselWindow = mountBrowserSurface(
            safeAreaInsets: safeAreaInsets,
            content: ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    MobileBrowserLivePageView(
                        page: cardPage,
                        viewport: viewport
                    )
                    .containerRelativeFrame(.horizontal)
                }
                .scrollTargetLayout()
            }
            .ignoresSafeArea(.container, edges: .vertical)
        )
        defer {
            singleWindow.isHidden = true
            carouselWindow.isHidden = true
        }

        let singleHost = try XCTUnwrap(firstWebHostView(in: singleWindow))
        let cardHost = try XCTUnwrap(firstWebHostView(in: carouselWindow))

        XCTAssertEqual(
            singleHost.bounds.height,
            carouselWindow.bounds.height,
            accuracy: 0.5,
            "The single page is full-bleed, so its host spans the window."
        )
        XCTAssertEqual(
            cardHost.bounds.height,
            carouselWindow.bounds.height,
            accuracy: 0.5,
            "A carousel cell is full-bleed too, so its host spans the window."
        )
        XCTAssertEqual(
            singlePage.webView.convert(singlePage.webView.bounds, to: singleWindow).minY,
            safeAreaInsets.top,
            accuracy: 0.5,
            "The single page starts its web content below the status bar."
        )
        XCTAssertEqual(
            cardPage.webView.convert(cardPage.webView.bounds, to: carouselWindow).minY,
            safeAreaInsets.top,
            accuracy: 0.5,
            """
            A split card must start its web content on the same row as the \
            single page instead of drawing behind the status bar.
            """
        )
        XCTAssertEqual(
            cardPage.webView.obscuredContentInsets.bottom,
            singlePage.webView.obscuredContentInsets.bottom,
            accuracy: 0.5,
            "Both paths report the same obscured bottom chrome to WebKit."
        )
        XCTAssertEqual(
            cardPage.webView.minimumViewportInset.bottom,
            singlePage.webView.minimumViewportInset.bottom,
            accuracy: 0.5
        )
        XCTAssertEqual(
            cardPage.webView.maximumViewportInset.bottom,
            singlePage.webView.maximumViewportInset.bottom,
            accuracy: 0.5
        )
    }

    func testHiddenToolbarUsesASmallerVisualChipWithoutShrinkingItsTapTarget() {
        XCTAssertLessThan(
            MobileCompactDomainChipLayout.visibleHeight,
            MobileCompactDomainChipLayout.minimumHitTarget
        )
        XCTAssertEqual(MobileCompactDomainChipLayout.visibleHeight, 36)
        XCTAssertEqual(MobileCompactDomainChipLayout.minimumHitTarget, 44)
        XCTAssertEqual(
            MobileBrowserViewportPolicy.compactDomainChipHeight,
            MobileCompactDomainChipLayout.minimumHitTarget
        )
        XCTAssertLessThan(
            MobileBrowserViewportPolicy.compactDomainChipHeight,
            MobileBrowserViewportPolicy.compactToolbarHeight
        )
    }

    func testAStaleMobileHostCannotStopNavigationAfterTheWebViewMoves() {
        let oldHost = MobileBrowserWebHostView()
        let newHost = MobileBrowserWebHostView()
        let webView = StopRecordingMobileWebView()

        oldHost.attach(webView)
        newHost.configureViewport(
            MobileBrowserPageViewport(
                obscuresSystemSafeAreas: true,
                systemSafeAreaInsets: .zero,
                bottomChromeHeight: MobileBrowserViewportPolicy.compactToolbarHeight
            )
        )
        newHost.attach(webView)
        oldHost.detach(stopsLoading: true)

        XCTAssertTrue(webView.superview === newHost)
        XCTAssertEqual(
            webView.stopLoadingCallCount,
            0,
            "A stale SwiftUI host must not cancel a navigation owned by the replacement host."
        )
        XCTAssertEqual(
            webView.scrollView.verticalScrollIndicatorInsets.bottom,
            MobileBrowserViewportPolicy.compactToolbarHeight,
            "A stale host must not clear viewport state applied by the replacement host."
        )
    }

    func testDismantlingMobileWebViewDoesNotCancelModelOwnedNavigation() {
        let host = MobileBrowserWebHostView()
        let coordinator = MobileBrowserWebView.Coordinator()
        let webView = StopRecordingMobileWebView()

        host.attach(webView)
        MobileBrowserWebView.dismantleUIView(host, coordinator: coordinator)

        XCTAssertNil(webView.superview)
        XCTAssertEqual(
            webView.stopLoadingCallCount,
            0,
            "SwiftUI host teardown must not cancel navigation owned by the retained page model."
        )
    }

    func testTransientCardsStayInsideTheSafeAreaInEveryDirection() {
        let insets = MobileBrowserTransientLayout.cardInsets(
            safeAreaInsets: EdgeInsets(top: 59, leading: 6, bottom: 34, trailing: 3),
            minimumHorizontal: 8,
            minimumVertical: 6
        )

        XCTAssertEqual(insets.top, 59)
        XCTAssertEqual(insets.leading, 8)
        XCTAssertEqual(insets.bottom, 34)
        XCTAssertEqual(insets.trailing, 8)
    }

    func testPeekCardStartsAsOneWebsiteSurfaceAtTheTouchPoint() {
        let source = BrowserPeekSourcePresentation(
            normalizedMinX: 0.12,
            normalizedMinY: 0.28,
            normalizedWidth: 0.34,
            normalizedHeight: 0.05,
            normalizedTouchX: 0.21,
            normalizedTouchY: 0.31,
            label: "Peek destination"
        )

        let transform = MobileBrowserTransientLayout.sourceCardTransform(for: source)

        XCTAssertEqual(transform.anchor.x, 0.21, accuracy: 0.000_001)
        XCTAssertEqual(transform.anchor.y, 0.31, accuracy: 0.000_001)
        XCTAssertEqual(transform.scaleX, 0.34, accuracy: 0.000_001)
        XCTAssertEqual(transform.scaleY, 0.05, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(transform.scaleX, 0.06)
        XCTAssertLessThanOrEqual(transform.scaleX, 0.42)
        XCTAssertGreaterThanOrEqual(transform.scaleY, 0.035)
        XCTAssertLessThanOrEqual(transform.scaleY, 0.24)
    }

    func testPeekCloseAndSpaceControlsShareOneMinimumHitHeight() {
        XCTAssertEqual(
            MobileBrowserTransientLayout.controlHeight,
            BrowserPeekChromePolicy.controlHeight
        )
        XCTAssertGreaterThanOrEqual(
            MobileBrowserTransientLayout.controlHeight,
            44
        )
    }

    func testPeekUsesTheSharedThemedSplitDestinationAction() {
        XCTAssertTrue(BrowserPeekChromePolicy.primaryActionOpensSelectedSpace)
        XCTAssertTrue(BrowserPeekChromePolicy.showsTrailingSpaceMenu)
        XCTAssertTrue(BrowserPeekChromePolicy.usesSpaceBackgroundTint)
        XCTAssertEqual(BrowserPeekChromePolicy.openInTitle, "Open In…")
        XCTAssertEqual(
            BrowserPeekChromePolicy.menuTitle(spaceName: "Work"),
            "Work"
        )
    }

    func testPeekUsesTheSharedFastSpringEntrance() {
        XCTAssertEqual(
            BrowserPeekPresentationPolicy.entranceAnimation,
            .spring(duration: 0.28, bounce: 0.2)
        )
    }

    func testMobileLinkPeekSuppressesWebKitsTransientLinkHighlight() throws {
        let space = makeSpace(index: 47)
        let tab = try XCTUnwrap(space.tabs.first)
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )
        let peekBridgeSource = try XCTUnwrap(
            page.webView.configuration.userContentController.userScripts.first {
                $0.source.contains("crestLinkPeekPress")
            }?.source
        )

        XCTAssertFalse(page.webView.allowsLinkPreview)
        XCTAssertTrue(peekBridgeSource.contains("-webkit-tap-highlight-color"))
        XCTAssertTrue(peekBridgeSource.contains("transparent"))
    }

    func testFaviconDataURLDecoderAcceptsBoundedImagesOnly() {
        let favicon = Data([0x89, 0x50, 0x4E, 0x47])
        let dataURL = "data:image/png;base64,\(favicon.base64EncodedString())"

        XCTAssertEqual(BrowserFaviconCapture.decodeDataURL(dataURL), favicon)
        XCTAssertNil(BrowserFaviconCapture.decodeDataURL("data:text/plain;base64,SGVsbG8="))

        let oversized = Data(
            repeating: 0x01,
            count: BrowserFaviconCapture.maximumByteCount + 1
        )
        XCTAssertNil(
            BrowserFaviconCapture.decodeDataURL(
                "data:image/png;base64,\(oversized.base64EncodedString())"
            )
        )
    }

    func testFaviconDecoderCreatesABoundedImageOffTheViewBodyPath() async throws {
        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        let decoded = await BrowserFaviconImageDecoder.decode(png, maximumPixelSize: 64)
        let image = try XCTUnwrap(decoded)

        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
    }

    /// The keyboard's ⌥⌘←/→ path, which the toolbar swipe no longer shares.
    /// Space switching by chord is untouched by the Split View routing.
    func testAdjacentSpaceSelectionWrapsWithoutChangingSpaceOrder() throws {
        let firstSpace = makeSpace(index: 11)
        let secondSpace = makeSpace(index: 12)
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [firstSpace, secondSpace],
                selectedSpaceID: firstSpace.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )

        XCTAssertEqual(browser.selectAdjacentSpace(.next), secondSpace.id)
        XCTAssertEqual(browser.selectedSpace?.id, secondSpace.id)
        XCTAssertEqual(browser.selectAdjacentSpace(.next), firstSpace.id)
        XCTAssertEqual(browser.selectAdjacentSpace(.previous), secondSpace.id)
        XCTAssertEqual(browser.session.spaces.map(\.id), [firstSpace.id, secondSpace.id])
    }

    func testKeyboardSpaceCommandsStillSwitchSpacesAfterTheSwipeStoppedDoingIt()
        throws
    {
        let firstSpace = makeSpace(index: 13)
        let secondSpace = makeSpace(index: 14)
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [firstSpace, secondSpace],
                selectedSpaceID: firstSpace.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let commands = MobileBrowserCommandController(browser: browser, pages: pages)

        XCTAssertEqual(commands.selectNextSpace(), secondSpace.id)
        XCTAssertEqual(browser.selectedSpace?.id, secondSpace.id)
        XCTAssertEqual(commands.selectPreviousSpace(), firstSpace.id)
        XCTAssertEqual(browser.selectedSpace?.id, firstSpace.id)
    }

    // MARK: - Toolbar swipe routing

    func testToolbarSwipeRoutesToCardsInsideASplitAndNowhereOutsideOne() {
        XCTAssertEqual(
            MobileToolbarSwipePolicy.destination(isInSplitGroup: true),
            .adjacentCard
        )
        XCTAssertEqual(
            MobileToolbarSwipePolicy.destination(isInSplitGroup: false),
            .none,
            """
            Replaces the old unconditional Space switch. The recognizer stays \
            installed so the gesture means one thing everywhere; outside a group \
            that one thing is nothing.
            """
        )
    }

    func testToolbarSwipeSelectsTheAdjacentCardAndClampsAtBothEnds() throws {
        let split = makeSplitFixture(selectedIndex: 0)
        let browser = try makeSplitBrowser(split)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let model = makeModel(browser: browser, pages: pages)
        pages.select(session: browser.session)

        XCTAssertNil(
            model.selectAdjacentSplitCard(.previous),
            "Clamped at the leading end rather than wrapping."
        )
        XCTAssertEqual(model.selectAdjacentSplitCard(.next), split.members[1].id)
        XCTAssertEqual(browser.selectedTab?.id, split.members[1].id)
        XCTAssertEqual(model.selectAdjacentSplitCard(.next), split.members[2].id)
        XCTAssertNil(model.selectAdjacentSplitCard(.next))
        XCTAssertEqual(model.selectAdjacentSplitCard(.previous), split.members[1].id)
    }

    func testToolbarSwipeOutsideASplitChangesNeitherCardNorSpace() throws {
        let firstSpace = makeSpace(index: 15)
        let secondSpace = makeSpace(index: 16)
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [firstSpace, secondSpace],
                selectedSpaceID: firstSpace.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let model = makeModel(browser: browser, pages: pages)
        let selectedTabID = browser.selectedTab?.id

        XCTAssertNil(model.selectAdjacentSplitCard(.next))
        XCTAssertEqual(browser.selectedTab?.id, selectedTabID)
        XCTAssertEqual(
            browser.selectedSpace?.id,
            firstSpace.id,
            "The swipe must not fall back to switching Spaces."
        )
    }

    func testSplitCardFocusMovesSelectionAndPresentationTogether() throws {
        let split = makeSplitFixture(selectedIndex: 0)
        let browser = try makeSplitBrowser(split)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let model = makeModel(browser: browser, pages: pages)
        pages.select(session: browser.session)

        model.focusSplitCard(split.members[2].id)

        XCTAssertEqual(browser.selectedTab?.id, split.members[2].id)
        XCTAssertEqual(pages.activePage?.tabID, split.members[2].id)
        XCTAssertEqual(pages.presentedTabIDs, split.members.map(\.id))
    }

    func testKeyboardSplitCardFocusCyclesWrapsAndSeparatesTheGroup() throws {
        let split = makeSplitFixture(selectedIndex: 0)
        let browser = try makeSplitBrowser(split)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let commands = MobileBrowserCommandController(browser: browser, pages: pages)
        pages.select(session: browser.session)

        XCTAssertTrue(commands.isSelectedTabInSplit)
        XCTAssertEqual(
            commands.focusAdjacentSplitCard(offset: -1),
            split.members[2].id,
            "A repeated chord cycles, unlike the spatial swipe."
        )
        XCTAssertEqual(
            commands.focusAdjacentSplitCard(offset: 1),
            split.members[0].id
        )

        XCTAssertNotNil(commands.separateSplitTabs())
        XCTAssertFalse(commands.isSelectedTabInSplit)
        XCTAssertEqual(pages.presentedTabIDs.count, 1)
    }

    // MARK: - Split fixtures

    private func makeSplitFixture(
        selectedIndex: Int
    ) -> (space: BrowserSpace, members: [BrowserTab]) {
        let groupID = SplitGroupID(rawValue: fixedUUID(0x6000))
        let members = (0..<3).map { index in
            BrowserTab(
                id: TabID(rawValue: fixedUUID(0x6100 + index)),
                title: "Card \(index)",
                url: URL(string: "https://cards.crest.test/\(index)"),
                placement: .current,
                splitGroupID: groupID
            )
        }
        let space = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(0x6200)),
            profile: BrowsingProfile(id: fixedUUID(0x6300)),
            name: "Split",
            symbol: "rectangle.split.2x1",
            accent: .indigo,
            folders: [],
            tabs: members,
            selectedTabID: members[selectedIndex].id
        )
        return (space, members)
    }

    private func makeSplitBrowser(
        _ split: (space: BrowserSpace, members: [BrowserTab])
    ) throws -> BrowserStore {
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [split.space],
                selectedSpaceID: split.space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let space = try XCTUnwrap(browser.selectedSpace)
        XCTAssertEqual(
            space.splitGroup(containing: split.members[0].id),
            split.members[0].splitGroupID,
            "The fixture must survive repair as one renderable run."
        )
        return browser
    }

    private func makeModel(
        browser: BrowserStore,
        pages: MobileBrowserPageStore
    ) -> MobileBrowserRootModel {
        MobileBrowserRootModel(
            browser: browser,
            pages: pages,
            navigation: MobileBrowserNavigationState(),
            spaceAccess: BrowserSpaceAccessController(
                authenticator: BrowserPreviewAuthenticator(result: false)
            ),
            windowState: nil,
            startupBehavior: .waitForTabSelection,
            persistedSidebarWidth: MobileBrowserRootLayout.defaultRegularSidebarWidth
        )
    }

    func testPageStoreRetainsTabsButNeverReusesAProfileAcrossSpaces() throws {
        let firstSpace = makeSpace(index: 1)
        let secondSpace = makeSpace(index: 2)
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [firstSpace, secondSpace],
                selectedSpaceID: firstSpace.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )

        pages.select(session: browser.session)
        let firstPage = try XCTUnwrap(pages.activePage)
        XCTAssertEqual(firstPage.profileID, firstSpace.profile.id)

        browser.selectSpace(secondSpace.id)
        pages.select(session: browser.session)
        let secondPage = try XCTUnwrap(pages.activePage)
        XCTAssertEqual(secondPage.profileID, secondSpace.profile.id)
        XCTAssertFalse(firstPage === secondPage)

        browser.selectSpace(firstSpace.id)
        pages.select(session: browser.session)
        XCTAssertTrue(try XCTUnwrap(pages.activePage) === firstPage)
    }

    func testPageStoreAppliesAndReconcilesContentBlockingPerSpace() async throws {
        let store = try isolatedRuleListStore()
        let ruleList = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.mobile-policy.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "never-match\\.crest-test$"),
            store: store
        )
        let provider = StubMobileContentRuleListProvider(generations: [[ruleList]])
        let space = makeSpace(index: 28)
        var session = BrowserSession(
            spaces: [space],
            selectedSpaceID: space.id
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true,
            contentRuleListProvider: provider
        )

        await pages.prepareContentBlocking()
        XCTAssertEqual(provider.requestCount, 1)
        pages.select(session: session)
        XCTAssertEqual(pages.activePage?.isContentBlockingActive, true)
        let transientLease = try XCTUnwrap(
            pages.makeTransientPageLease(
                url: URL(string: "about:blank")!,
                in: space
            )
        )
        XCTAssertEqual(transientLease.page?.isContentBlockingActive, true)

        var preferences = try XCTUnwrap(
            session.selectedSpace?.browsingPreferences
        )
        preferences.contentBlockingPolicy = .off
        session.updateBrowsingPreferences(preferences, in: space.id)
        await pages.reconcileContentBlocking(in: session)

        XCTAssertEqual(pages.activePage?.isContentBlockingActive, false)
        XCTAssertEqual(transientLease.page?.isContentBlockingActive, false)

        transientLease.setActive(false)
        pages.handleMemoryPressure(.warning)
        XCTAssertNil(transientLease.page)
        transientLease.restore()
        XCTAssertEqual(transientLease.page?.isContentBlockingActive, false)
    }

    func testFilterListUpdateSwapsMobileRulesWithoutReloadingResidentPages() async throws {
        let documents = try MobileTrackerDocuments()
        defer { documents.remove() }
        let store = try isolatedRuleListStore()
        let firstGeneration = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.mobile-first.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "first-tracker\\.js$"),
            store: store
        )
        let secondGeneration = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.mobile-second.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "second-tracker\\.js$"),
            store: store
        )
        let provider = StubMobileContentRuleListProvider(
            generations: [[firstGeneration], [secondGeneration]]
        )
        let activeTab = BrowserTab.startPage()
        let backgroundTab = BrowserTab.startPage()
        let space = contentBlockingSpace(tabs: [activeTab, backgroundTab])
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true,
            contentRuleListProvider: provider
        )

        await pages.prepareContentBlocking()
        session.selectTab(backgroundTab.id)
        pages.select(session: session)
        let backgroundPage = try XCTUnwrap(pages.activePage)
        session.selectTab(activeTab.id)
        pages.select(session: session)
        let activePage = try XCTUnwrap(pages.activePage)
        XCTAssertFalse(activePage === backgroundPage)

        for page in [activePage, backgroundPage] {
            try await documents.load(into: page)
            let trackers = try await documents.trackerState(in: page)
            XCTAssertEqual(trackers, [false, true])
            try await documents.markSentinel(in: page)
        }
        let activeNavigationCount = activePage.completedNavigationCount
        let backgroundNavigationCount = backgroundPage.completedNavigationCount

        await pages.reloadContentBlocking(in: session)

        try await Task.sleep(for: .milliseconds(400))
        for (page, navigationCount) in [
            (activePage, activeNavigationCount),
            (backgroundPage, backgroundNavigationCount),
        ] {
            let keptSentinel = try await documents.hasSentinel(in: page)
            let trackers = try await documents.trackerState(in: page)
            XCTAssertEqual(page.completedNavigationCount, navigationCount)
            XCTAssertFalse(page.isLoading)
            XCTAssertTrue(keptSentinel)
            XCTAssertEqual(trackers, [false, true])
            XCTAssertEqual(page.isContentBlockingActive, true)
        }

        for page in [activePage, backgroundPage] {
            try await documents.load(into: page)
            let trackers = try await documents.trackerState(in: page)
            XCTAssertEqual(trackers, [true, false])
        }
    }

    func testProtectionChangeReloadsTheActiveMobilePageAndOnlyThatPage() async throws {
        let documents = try MobileTrackerDocuments()
        defer { documents.remove() }
        let store = try isolatedRuleListStore()
        let ruleList = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.mobile-protection.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "first-tracker\\.js$"),
            store: store
        )
        let provider = StubMobileContentRuleListProvider(generations: [[ruleList]])
        let activeTab = BrowserTab.startPage()
        let backgroundTab = BrowserTab.startPage()
        let space = contentBlockingSpace(tabs: [activeTab, backgroundTab])
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true,
            contentRuleListProvider: provider
        )

        await pages.prepareContentBlocking()
        session.selectTab(backgroundTab.id)
        pages.select(session: session)
        let backgroundPage = try XCTUnwrap(pages.activePage)
        session.selectTab(activeTab.id)
        pages.select(session: session)
        let activePage = try XCTUnwrap(pages.activePage)
        // Adopts the Space's current protection level the way launching does.
        // Nothing may reload for it.
        await pages.reconcileContentBlocking(in: session)

        for page in [activePage, backgroundPage] {
            try await documents.load(into: page)
            try await documents.markSentinel(in: page)
        }
        let activeNavigationCount = activePage.completedNavigationCount
        let backgroundNavigationCount = backgroundPage.completedNavigationCount

        var preferences = try XCTUnwrap(
            session.space(id: space.id)?.browsingPreferences
        )
        preferences.contentBlockingPolicy = .off
        session.updateBrowsingPreferences(preferences, in: space.id)
        await pages.reconcileContentBlocking(in: session)

        try await documents.waitForNavigation(
            after: activeNavigationCount,
            on: activePage
        )
        let activeSentinel = try await documents.hasSentinel(in: activePage)
        let activeTrackers = try await documents.trackerState(in: activePage)
        XCTAssertFalse(activeSentinel)
        XCTAssertEqual(activeTrackers, [true, true])
        XCTAssertEqual(activePage.isContentBlockingActive, false)

        let backgroundSentinel = try await documents.hasSentinel(in: backgroundPage)
        XCTAssertEqual(
            backgroundPage.completedNavigationCount,
            backgroundNavigationCount
        )
        XCTAssertFalse(backgroundPage.isLoading)
        XCTAssertTrue(backgroundSentinel)
        XCTAssertEqual(backgroundPage.isContentBlockingActive, false)
    }

    private func contentBlockingSpace(tabs: [BrowserTab]) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Protected",
            symbol: "shield",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs.first?.id
        )
    }

    private func blockingRuleSource(matching urlFilter: String) -> String {
        let rules: [[String: Any]] = [
            [
                "trigger": [
                    "url-filter": urlFilter,
                    "resource-type": ["script"],
                ],
                "action": ["type": "block"],
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(decoding: data, as: UTF8.self)
    }

    /// A rule-list store of its own, so a test never sweeps or reads compiled
    /// lists belonging to the app.
    private func isolatedRuleListStore() throws -> WKContentRuleListStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "crest-mobile-rule-list-store-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try XCTUnwrap(WKContentRuleListStore(url: directory))
    }

    func testDeletingASpacesMobileRuntimeDataPreservesAnotherSpace() async throws {
        let deletedSpace = makeSpace(index: 31)
        let retainedSpace = makeSpace(index: 32)
        let permissionCenter = BrowserSitePermissionCenter()
        let remover = RecordingMobileWebsiteDataStoreRemover()
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            permissionCenter: permissionCenter,
            websiteDataStoreRemover: remover
        )
        let origin = BrowserSiteOrigin(
            scheme: "https",
            host: "camera.crest.test",
            port: 443
        )
        permissionCenter.setDecision(
            .grantPersistently,
            for: .camera,
            origin: origin,
            in: deletedSpace.id
        )
        permissionCenter.setDecision(
            .denyPersistently,
            for: .camera,
            origin: origin,
            in: retainedSpace.id
        )
        pages.select(
            session: BrowserSession(
                spaces: [deletedSpace, retainedSpace],
                selectedSpaceID: deletedSpace.id
            )
        )
        XCTAssertFalse(
            try XCTUnwrap(
                pages.activePage?.webView.configuration.websiteDataStore
            ).isPersistent
        )
        pages.select(
            session: BrowserSession(
                spaces: [deletedSpace, retainedSpace],
                selectedSpaceID: retainedSpace.id
            )
        )
        XCTAssertFalse(
            try XCTUnwrap(
                pages.activePage?.webView.configuration.websiteDataStore
            ).isPersistent
        )
        let deletedTabID = try XCTUnwrap(deletedSpace.selectedTabID)
        let retainedTabID = try XCTUnwrap(retainedSpace.selectedTabID)

        try await pages.deleteData(for: deletedSpace)

        XCTAssertFalse(pages.containsResidentPage(for: deletedTabID))
        XCTAssertTrue(pages.containsResidentPage(for: retainedTabID))
        XCTAssertEqual(pages.activePage?.tabID, retainedTabID)
        XCTAssertTrue(permissionCenter.records(in: deletedSpace.id).isEmpty)
        XCTAssertEqual(
            permissionCenter.records(in: retainedSpace.id).map(\.decision),
            [.denyPersistently]
        )
        XCTAssertEqual(remover.removedProfileIDs, [deletedSpace.profile.id])
    }

    func testDeletingSpaceThroughMobileRegistryReleasesEveryWindowBeforeSharedData() async throws {
        let space = makeSpace(index: 35)
        let tabID = try XCTUnwrap(space.selectedTabID)
        let remover = RecordingMobileWebsiteDataStoreRemover()
        let primaryPages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            websiteDataStoreRemover: remover
        )
        let secondaryPages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true,
            websiteDataStoreRemover: remover
        )
        let registry = MobileBrowserPageStoreRegistry(primary: primaryPages)
        registry.register(secondaryPages)
        let session = BrowserSession(
            spaces: [space],
            selectedSpaceID: space.id
        )
        primaryPages.select(session: session)
        secondaryPages.select(session: session)
        XCTAssertFalse(
            try XCTUnwrap(
                primaryPages.activePage?.webView.configuration.websiteDataStore
            ).isPersistent
        )
        XCTAssertFalse(
            try XCTUnwrap(
                secondaryPages.activePage?.webView.configuration.websiteDataStore
            ).isPersistent
        )

        try await registry.deleteData(for: space)

        XCTAssertFalse(primaryPages.containsResidentPage(for: tabID))
        XCTAssertFalse(secondaryPages.containsResidentPage(for: tabID))
        XCTAssertEqual(remover.removedProfileIDs, [space.profile.id])
    }

    func testSpaceCannotRecreateItsPageWhileProfileDeletionIsSuspended() async throws {
        let deletedSpace = makeSpace(index: 33)
        let remover = SuspendingMobileWebsiteDataStoreRemover()
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: false,
            websiteDataStoreRemover: remover
        )
        let deletedSession = BrowserSession(
            spaces: [deletedSpace],
            selectedSpaceID: deletedSpace.id
        )
        pages.select(session: deletedSession)
        XCTAssertNotNil(pages.activePage)
        XCTAssertFalse(
            try XCTUnwrap(
                pages.activePage?.webView.configuration.websiteDataStore
            ).isPersistent
        )

        let deletion = Task {
            try await pages.deleteData(for: deletedSpace)
        }
        await remover.waitUntilRemovalStarts()

        pages.select(session: deletedSession)

        XCTAssertNil(pages.activePage)
        XCTAssertEqual(pages.residentPageCount, 0)

        remover.finishRemoval()
        try await deletion.value
    }

    func testPageStoreKeepsEveryActivatedPageWithoutACountBasedLimit() throws {
        let tabs = (1...4).map { index in
            BrowserTab(
                id: TabID(rawValue: fixedUUID(300 + index)),
                title: "Tab \(index)",
                url: nil,
                symbol: "globe",
                placement: .current
            )
        }
        let space = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(350)),
            profile: BrowsingProfile(id: fixedUUID(351)),
            name: "Memory",
            symbol: "memorychip",
            accent: .teal,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs[0].id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        for tab in tabs {
            browser.selectTab(tab.id)
            pages.select(session: browser.session)
        }

        XCTAssertEqual(pages.residentPageCount, tabs.count)
        XCTAssertTrue(tabs.allSatisfy { pages.containsResidentPage(for: $0.id) })
    }

    func testMobileSwitchingTabsKeepsThePageResidentWithoutAnIdleTimer() {
        let reddit = BrowserTab(title: "Reddit", url: nil, placement: .current)
        let crest = BrowserTab(title: "Crest", url: nil, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase",
            accent: .indigo,
            folders: [],
            tabs: [reddit, crest],
            selectedTabID: reddit.id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        let switchTime = Date(timeIntervalSince1970: 1_000)

        pages.select(
            session: browser.session,
            at: switchTime.addingTimeInterval(-1)
        )
        browser.selectTab(crest.id)
        pages.select(session: browser.session, at: switchTime)

        XCTAssertTrue(pages.containsResidentPage(for: reddit.id))
        XCTAssertTrue(pages.containsResidentPage(for: crest.id))

        pages.select(session: browser.session, at: .distantFuture)
        XCTAssertTrue(pages.containsResidentPage(for: reddit.id))
        XCTAssertTrue(pages.containsResidentPage(for: crest.id))
    }

    func testMobileInactivePageDoesNotAutomaticallyUnloadWithTime() async {
        let first = BrowserTab(title: "First", url: nil, placement: .current)
        let second = BrowserTab(title: "Second", url: nil, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase",
            accent: .indigo,
            folders: [],
            tabs: [first, second],
            selectedTabID: first.id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)

        pages.select(session: browser.session)
        browser.selectTab(second.id)
        pages.select(session: browser.session)

        XCTAssertTrue(pages.containsResidentPage(for: first.id))
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(pages.containsResidentPage(for: first.id))
        XCTAssertTrue(pages.containsResidentPage(for: second.id))
    }

    func testMobileSessionSelectionDoesNotForcePinnedSiblingsToLoad() {
        let firstPinned = BrowserTab(title: "First", url: nil, placement: .pinned)
        let secondPinned = BrowserTab(title: "Second", url: nil, placement: .pinned)
        let current = BrowserTab(title: "Current", url: nil, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Pinned",
            symbol: "pin",
            accent: .indigo,
            folders: [],
            tabs: [firstPinned, secondPinned, current],
            selectedTabID: current.id
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )

        pages.select(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id)
        )

        XCTAssertEqual(pages.residentPageCount, 1)
        XCTAssertTrue(pages.containsResidentPage(for: current.id))
        XCTAssertFalse(pages.containsResidentPage(for: firstPinned.id))
        XCTAssertFalse(pages.containsResidentPage(for: secondPinned.id))
    }

    func testMobilePinnedPagesOnlyLoadWhenTheUserSelectsThem() {
        let firstPinned = BrowserTab(title: "First", url: nil, placement: .pinned)
        let secondPinned = BrowserTab(title: "Second", url: nil, placement: .pinned)
        let current = BrowserTab(title: "Current", url: nil, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Pinned",
            symbol: "pin",
            accent: .indigo,
            folders: [],
            tabs: [firstPinned, secondPinned, current],
            selectedTabID: current.id
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )

        pages.select(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id)
        )

        XCTAssertTrue(pages.containsResidentPage(for: current.id))
        XCTAssertFalse(pages.containsResidentPage(for: firstPinned.id))
        XCTAssertFalse(pages.containsResidentPage(for: secondPinned.id))
        XCTAssertEqual(pages.residentPageCount, 1)

        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        browser.selectTab(secondPinned.id)
        pages.select(session: browser.session)

        XCTAssertTrue(pages.containsResidentPage(for: secondPinned.id))
        XCTAssertEqual(pages.activePage?.tabID, secondPinned.id)
        XCTAssertEqual(pages.residentPageCount, 2)
    }

    func testMobileSpaceSwitchingLoadsOnlyEachSpacesSelectedTab() throws {
        let spaces = (1...3).map { spaceIndex in
            let pins = (1...BrowserSpace.maximumPinnedTabs).map { pinIndex in
                BrowserTab(
                    title: "Space \(spaceIndex) pinned \(pinIndex)",
                    url: nil,
                    symbol: "pin",
                    placement: .pinned
                )
            }
            let current = BrowserTab(
                title: "Space \(spaceIndex) current",
                url: nil,
                symbol: "globe",
                placement: .current
            )
            return BrowserSpace(
                id: SpaceID(),
                profile: BrowsingProfile(),
                name: "Many Pins \(spaceIndex)",
                symbol: "pin",
                accent: .indigo,
                folders: [],
                tabs: pins + [current],
                selectedTabID: current.id
            )
        }
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: spaces,
                selectedSpaceID: spaces[0].id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )

        for (index, space) in spaces.enumerated() {
            browser.selectSpace(space.id)
            pages.select(session: browser.session)
            XCTAssertEqual(pages.residentPageCount, index + 1)
            XCTAssertTrue(
                pages.containsResidentPage(for: try XCTUnwrap(space.selectedTabID))
            )
            XCTAssertTrue(
                space.pinnedTabs.allSatisfy {
                    !pages.containsResidentPage(for: $0.id)
                }
            )
        }

        for pin in spaces[2].pinnedTabs.reversed() {
            browser.selectTab(pin.id)
            pages.select(session: browser.session)
            XCTAssertEqual(pages.activePage?.tabID, pin.id)
        }
        XCTAssertEqual(
            pages.residentPageCount,
            spaces.count + spaces[2].pinnedTabs.count
        )
    }

    func testPageStoreUnloadsAndRehydratesAPinnedTabWithoutRemovingItsModel() {
        let pinned = BrowserTab(
            id: TabID(rawValue: fixedUUID(330)),
            title: "Pinned",
            url: nil,
            symbol: "globe",
            placement: .pinned
        )
        let current = BrowserTab(
            id: TabID(rawValue: fixedUUID(331)),
            title: "Current",
            url: nil,
            symbol: "globe",
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(332)),
            profile: BrowsingProfile(id: fixedUUID(333)),
            name: "Unload",
            symbol: "minus.circle",
            accent: .teal,
            folders: [],
            tabs: [pinned, current],
            selectedTabID: pinned.id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )

        pages.select(session: browser.session)
        browser.selectTab(current.id)
        pages.select(session: browser.session)
        pages.unloadPage(for: pinned.id)

        XCTAssertFalse(pages.containsResidentPage(for: pinned.id))
        XCTAssertNotNil(browser.selectedSpace?.tabs.first(where: { $0.id == pinned.id }))

        browser.selectTab(pinned.id)
        pages.select(session: browser.session)
        XCTAssertTrue(pages.containsResidentPage(for: pinned.id))
        XCTAssertEqual(pages.activePage?.tabID, pinned.id)
    }

    func testCapturedMobileUnloadRejectsAReplacementResidentPageAssignment() {
        let pinned = BrowserTab(
            id: TabID(rawValue: fixedUUID(334)),
            title: "Replacement resident",
            url: nil,
            symbol: "globe",
            placement: .pinned
        )
        let original = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(335)),
            profile: BrowsingProfile(id: fixedUUID(336)),
            name: "Original",
            symbol: "minus.circle",
            accent: .teal,
            folders: [],
            tabs: [pinned],
            selectedTabID: pinned.id
        )
        let replacement = BrowserSpace(
            id: original.id,
            profile: BrowsingProfile(id: fixedUUID(337)),
            name: original.name,
            symbol: original.symbol,
            accent: original.accent,
            branding: original.branding,
            folders: original.folders,
            tabs: original.tabs,
            archivedTabs: original.archivedTabs,
            history: original.history,
            browsingPreferences: original.browsingPreferences,
            credentialPreferences: original.credentialPreferences,
            accessPolicy: original.accessPolicy,
            isSavedTabsExpanded: original.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: original.savedTabsExpansionModifiedAt,
            selectedTabID: original.selectedTabID
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        pages.select(
            session: BrowserSession(
                spaces: [replacement],
                selectedSpaceID: replacement.id
            )
        )

        XCTAssertFalse(
            pages.unloadPage(
                for: pinned.id,
                matching: BrowserSpaceRuntimeAssignment(space: original)
            )
        )
        XCTAssertTrue(pages.containsResidentPage(for: pinned.id))
        XCTAssertEqual(pages.activePage?.profileID, replacement.profile.id)
    }

    func testPageStoreWarningPressureKeepsOrdinaryTabsResident() async throws {
        let tabs = (1...4).map { index in
            BrowserTab(
                id: TabID(rawValue: fixedUUID(400 + index)),
                title: "Tab \(index)",
                url: nil,
                symbol: "globe",
                placement: .current
            )
        }
        let space = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(450)),
            profile: BrowsingProfile(id: fixedUUID(451)),
            name: "Pressure",
            symbol: "memorychip",
            accent: .teal,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs[0].id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )

        for tab in tabs {
            browser.selectTab(tab.id)
            pages.select(session: browser.session)
        }

        let activePage = try XCTUnwrap(pages.activePage)
        pages.handleMemoryPressure(.warning)
        await pages.waitForPendingMemoryPressureResponse()

        XCTAssertEqual(pages.residentPageCount, tabs.count)
        XCTAssertTrue(pages.containsResidentPage(for: tabs[3].id))
        XCTAssertTrue(try XCTUnwrap(pages.activePage) === activePage)
        XCTAssertTrue(pages.containsResidentPage(for: tabs[0].id))
    }

    func testPageStoreCriticalPressureUnloadsOnlyTheOldestEligibleTab() async throws {
        let tabs = (1...8).map { index in
            BrowserTab(
                id: TabID(rawValue: fixedUUID(460 + index)),
                title: "Tab \(index)",
                url: nil,
                symbol: "globe",
                placement: .current
            )
        }
        let space = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(470)),
            profile: BrowsingProfile(id: fixedUUID(471)),
            name: "Coalescing",
            symbol: "memorychip",
            accent: .teal,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs[0].id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        let squeeze = Date()

        for tab in tabs {
            browser.selectTab(tab.id)
            pages.select(session: browser.session)
        }

        pages.handleMemoryPressure(.critical, at: squeeze)
        await pages.waitForPendingMemoryPressureResponse()

        XCTAssertEqual(pages.residentPageCount, tabs.count - 1)
        XCTAssertFalse(pages.containsResidentPage(for: tabs[0].id))
        XCTAssertTrue(pages.containsResidentPage(for: tabs[7].id))
        XCTAssertEqual(pages.activePage?.tabID, tabs[7].id)
    }

    func testPageStoreCriticalPressureHonorsManualKeepLoaded() async throws {
        let pinned = (1...2).map { index in
            BrowserTab(
                id: TabID(rawValue: fixedUUID(480 + index)),
                title: "Pinned \(index)",
                url: nil,
                symbol: "pin",
                placement: .pinned,
                keepsPageLoaded: index == 1
            )
        }
        let current = (1...3).map { index in
            BrowserTab(
                id: TabID(rawValue: fixedUUID(490 + index)),
                title: "Current \(index)",
                url: nil,
                symbol: "globe",
                placement: .current
            )
        }
        let space = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(500)),
            profile: BrowsingProfile(id: fixedUUID(501)),
            name: "Pinned pressure",
            symbol: "memorychip",
            accent: .teal,
            folders: [],
            tabs: pinned + current,
            selectedTabID: current[0].id
        )
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )

        for tab in pinned + current {
            browser.selectTab(tab.id)
            pages.select(session: browser.session)
        }
        XCTAssertEqual(pages.residentPageCount, 5)

        pages.handleMemoryPressure(.critical)
        await pages.waitForPendingMemoryPressureResponse()

        XCTAssertEqual(pages.residentPageCount, 4)
        XCTAssertTrue(pages.containsResidentPage(for: pinned[0].id))
        XCTAssertFalse(pages.containsResidentPage(for: pinned[1].id))
        XCTAssertTrue(pages.containsResidentPage(for: current[2].id))
        XCTAssertEqual(pages.activePage?.tabID, current[2].id)
    }

    func testMobilePageStopsAfterTwoAutomaticWebContentReloads() {
        let space = makeSpace(index: 9)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            openNewTab: { _ in }
        )
        // Only a page the user can see is reloaded automatically, so the recovery
        // cap is a property of an on-screen page.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(page.webView)
        XCTAssertNotNil(page.webView.window)

        page.recordWebContentTermination()
        XCTAssertFalse(page.showsProcessFailure)
        page.recordWebContentTermination()
        XCTAssertFalse(page.showsProcessFailure)
        page.recordWebContentTermination()
        XCTAssertTrue(page.showsProcessFailure)

        page.retryAfterProcessFailure()
        XCTAssertFalse(page.showsProcessFailure)
        page.webView.removeFromSuperview()
    }

    func testMobilePageStoreRoutesZoomCommandsToTheActivePage() throws {
        let space = makeSpace(index: 10)
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )

        pages.select(session: BrowserSession(spaces: [space], selectedSpaceID: space.id))
        let page = try XCTUnwrap(pages.activePage)

        pages.zoomIn()
        XCTAssertEqual(page.pageZoom, 1.1, accuracy: 0.001)
        XCTAssertEqual(page.webView.pageZoom, 1.1, accuracy: 0.001)
        XCTAssertEqual(pages.pageZoomLabel, "110%")
        XCTAssertEqual(pages.pageZoomFeedbackLabel, "110%")
        XCTAssertEqual(pages.pageZoomFeedbackRevision, 1)

        pages.zoomOut()
        XCTAssertEqual(page.pageZoom, 1, accuracy: 0.001)

        pages.zoomOut()
        pages.resetZoom()
        XCTAssertEqual(page.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(pages.pageZoomLabel, "100%")
        XCTAssertEqual(pages.pageZoomFeedbackLabel, "100%")
        XCTAssertEqual(pages.pageZoomFeedbackRevision, 4)
    }

    func testMobileFindUsesWebKitAndClearsItsStateWhenDismissed() async throws {
        let space = makeSpace(index: 11)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            openNewTab: { _ in }
        )

        page.webView.loadHTMLString(
            "<html><body><p>Crest needle text</p></body></html>",
            baseURL: URL(string: "https://example.test/page")!
        )
        try await waitUntil(timeout: .seconds(8)) {
            page.completedNavigationCount == 1 && page.url != nil
        }

        page.presentFind()
        XCTAssertTrue(page.isFindPresented)

        page.find("needle")
        try await waitUntil { page.findMatchState != .searching }
        XCTAssertEqual(page.findMatchState, .found)

        page.find("missing phrase")
        try await waitUntil { page.findMatchState != .searching }
        XCTAssertEqual(page.findMatchState, .notFound)

        page.dismissFind()
        XCTAssertFalse(page.isFindPresented)
        XCTAssertEqual(page.findMatchState, .idle)
    }

    func testMobileReaderModeUsesTheRetainedInspectableSpacePage() async throws {
        let space = makeSpace(index: 15)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            openNewTab: { _ in }
        )
        let originalDataStore = page.webView.configuration.websiteDataStore
        let paragraph = String(
            repeating:
                "Crest presents readable articles without leaving the selected Space or its private data store. ",
            count: 8
        )

        page.webView.loadHTMLString(
            """
            <html><body><nav>Outside navigation</nav><article>
              <h1>Mobile Reader</h1>
              <p>\(paragraph)</p><p>\(paragraph)</p>
            </article></body></html>
            """,
            baseURL: URL(string: "https://reader.crest.test/mobile")
        )
        try await waitUntil {
            page.completedNavigationCount == 1 && page.readerModeState == .available
        }

        // Web Inspector is development tooling on iOS, not a shipped feature, so
        // release builds deliberately leave the web view uninspectable.
        #if DEBUG
            XCTAssertTrue(page.webView.isInspectable)
        #else
            XCTAssertFalse(page.webView.isInspectable)
        #endif
        try await page.setReaderModeActive(true)
        XCTAssertEqual(page.readerModeState, .active)
        XCTAssertTrue(page.webView.configuration.websiteDataStore === originalDataStore)

        let snapshot = try await BrowserReaderModeController.snapshot(in: page.webView)
        XCTAssertTrue(snapshot.isActive)
        XCTAssertEqual(snapshot.title, "Mobile Reader")
        XCTAssertFalse(snapshot.text.contains("Outside navigation"))

        try await page.setReaderModeActive(false)
        XCTAssertEqual(page.readerModeState, .available)
    }

    func testMobilePageUsesStandardsThemeColorForItsSurroundingWebView() async throws {
        let space = makeSpace(index: 14)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            openNewTab: { _ in }
        )
        page.webView.loadHTMLString(
            "<html><head><meta name='theme-color' content='#123456'></head><body>Theme</body></html>",
            baseURL: URL(string: "https://theme.crest.test")
        )

        try await waitUntil {
            page.completedNavigationCount == 1 && page.themeColor != nil
        }

        let themeColor = try XCTUnwrap(page.themeColor)
        let underPageColor = try XCTUnwrap(page.webView.underPageBackgroundColor)
        XCTAssertTrue(themeColor.isEqual(underPageColor))

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(
            themeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        )
        XCTAssertEqual(red, 0x12 as CGFloat / 255, accuracy: 0.02)
        XCTAssertEqual(green, 0x34 as CGFloat / 255, accuracy: 0.02)
        XCTAssertEqual(blue, 0x56 as CGFloat / 255, accuracy: 0.02)
        XCTAssertEqual(alpha, 1, accuracy: 0.01)
    }

    func testMobileLoadedPageCreatesARealPDFDocument() async throws {
        let space = makeSpace(index: 12)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            openNewTab: { _ in }
        )
        page.webView.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        page.webView.loadHTMLString(
            "<html><body><h1>Crest PDF Export</h1><p>Rendered by WebKit.</p></body></html>",
            baseURL: URL(string: "https://pdf.crest.test")
        )
        try await waitUntil { page.completedNavigationCount == 1 && page.url != nil }

        let data = try await page.pdfData()
        let document = try XCTUnwrap(
            CGPDFDocument(CGDataProvider(data: data as CFData)!)
        )

        XCTAssertGreaterThan(data.count, 500)
        XCTAssertGreaterThanOrEqual(document.numberOfPages, 1)
    }

    func testMobileLoadedPageCreatesARealWebKitWebArchive() async throws {
        let space = makeSpace(index: 13)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            openNewTab: { _ in }
        )
        page.webView.loadHTMLString(
            "<html><body><h1>Crest Mobile Web Archive</h1><p>Rendered by WebKit.</p></body></html>",
            baseURL: URL(string: "https://archive.crest.test")
        )
        try await waitUntil { page.completedNavigationCount == 1 && page.url != nil }

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
        XCTAssertTrue(
            String(decoding: resourceData, as: UTF8.self)
                .contains("Crest Mobile Web Archive")
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the browser state to change.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func makeSpace(index: Int) -> BrowserSpace {
        let tab = BrowserTab.startPage(
            id: TabID(rawValue: fixedUUID(index * 10 + 1)),
            placement: .current
        )
        return BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(index * 10 + 2)),
            profile: BrowsingProfile(id: fixedUUID(index * 10 + 3)),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    /// Hosts a compact browser surface in a window whose safe area stands in for
    /// a notched iPhone, laid out far enough to attach its web views.
    private func mountBrowserSurface(
        safeAreaInsets: UIEdgeInsets,
        content: some View
    ) -> UIWindow {
        let controller = UIHostingController(rootView: content)
        controller.additionalSafeAreaInsets = safeAreaInsets
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.layoutIfNeeded()
        return window
    }

    private func firstWebHostView(in view: UIView) -> MobileBrowserWebHostView? {
        if let host = view as? MobileBrowserWebHostView { return host }
        for subview in view.subviews {
            if let host = firstWebHostView(in: subview) { return host }
        }
        return nil
    }
}

private enum MobileContentBlockingTestError: Error {
    case navigationTimedOut
}

/// A local document with two tracker scripts and a sentinel a reload would wipe,
/// which is how these tests tell a rule-list swap from a reload.
@MainActor
private struct MobileTrackerDocuments {
    private let directory: URL
    private let documentURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "crest-mobile-content-blocking-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        documentURL = directory.appendingPathComponent("index.html")
        try Data(
            #"""
            <!doctype html><html><body>
              <p id="status">ready</p>
              <script src="first-tracker.js"></script>
              <script src="second-tracker.js"></script>
            </body></html>
            """#.utf8
        ).write(to: documentURL)
        try Data("window.crestFirstTrackerLoaded = true;".utf8).write(
            to: directory.appendingPathComponent("first-tracker.js")
        )
        try Data("window.crestSecondTrackerLoaded = true;".utf8).write(
            to: directory.appendingPathComponent("second-tracker.js")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func load(into page: MobileBrowserPage) async throws {
        let startingCount = page.completedNavigationCount
        page.webView.loadFileURL(documentURL, allowingReadAccessTo: directory)
        try await waitForNavigation(after: startingCount, on: page)
    }

    func waitForNavigation(
        after startingCount: Int,
        on page: MobileBrowserPage
    ) async throws {
        for _ in 0..<200 {
            if page.completedNavigationCount > startingCount { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw MobileContentBlockingTestError.navigationTimedOut
    }

    /// Whether each tracker script ran in the document that is loaded now.
    func trackerState(in page: MobileBrowserPage) async throws -> [Bool] {
        [
            try await boolean("window.crestFirstTrackerLoaded === true", in: page),
            try await boolean("window.crestSecondTrackerLoaded === true", in: page),
        ]
    }

    func markSentinel(in page: MobileBrowserPage) async throws {
        _ = try await page.webView.evaluateJavaScript(
            "window.crestSentinel = 'kept'; true"
        )
    }

    func hasSentinel(in page: MobileBrowserPage) async throws -> Bool {
        try await boolean("window.crestSentinel === 'kept'", in: page)
    }

    private func boolean(
        _ script: String,
        in page: MobileBrowserPage
    ) async throws -> Bool {
        try await page.webView.evaluateJavaScript(script) as? Bool ?? false
    }
}

/// Hands out one rule-list generation per request, standing in for the provider
/// recompiling after a filter-list update.
@MainActor
private final class StubMobileContentRuleListProvider: BrowserContentRuleListProviding {
    private let generations: [[WKContentRuleList]]
    private(set) var requestCount = 0

    init(generations: [[WKContentRuleList]]) {
        precondition(!generations.isEmpty)
        self.generations = generations
    }

    func balancedRuleLists() async throws -> [WKContentRuleList] {
        defer { requestCount += 1 }
        return generations[min(requestCount, generations.count - 1)]
    }
}

@MainActor
private final class StopRecordingMobileWebView: WKWebView {
    private(set) var stopLoadingCallCount = 0

    override func stopLoading() {
        stopLoadingCallCount += 1
        super.stopLoading()
    }
}

@MainActor
private final class SuspendingMobileWebsiteDataStoreRemover:
    BrowserWebsiteDataStoreRemoving
{
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var removalContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func removePersistentDataStore(
        for profile: BrowsingProfile
    ) async throws {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            removalContinuation = continuation
        }
    }

    func waitUntilRemovalStarts() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finishRemoval() {
        removalContinuation?.resume()
        removalContinuation = nil
    }
}

@MainActor
private final class RecordingMobileWebsiteDataStoreRemover:
    BrowserWebsiteDataStoreRemoving
{
    private(set) var removedProfileIDs: [UUID] = []

    func removePersistentDataStore(
        for profile: BrowsingProfile
    ) async throws {
        removedProfileIDs.append(profile.id)
    }
}
