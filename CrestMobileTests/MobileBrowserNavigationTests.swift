import SwiftUI
import UIKit
import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserNavigationTests: XCTestCase {

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

    func testLockedCompactDetailNeverAutomaticallyRestoresItsPage() throws {
        var locked = makeSpace(index: 195)
        let tab = BrowserTab(title: "Protected", url: URL(string: "about:blank"), placement: .current)
        locked.tabs = [tab]
        locked.selectedTabID = tab.id
        locked.accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore(
            session: BrowserSession(spaces: [locked], selectedSpaceID: locked.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let access = BrowserSpaceAccessController()
        let detail = MobileBrowserDetailView(
            browser: browser, pages: pages, spaceAccess: access,
            address: .constant(""), isAddressEditing: .constant(false),
            addressFocusRequest: 0, isCommandPalettePresented: false,
            isCompact: true, obscuresSystemSafeAreas: false,
            showsCompactToolbar: false, compactToolbarIsHidden: false,
            handleWebContentInteraction: {}, submitAddress: {}, beginNewTab: {},
            showTabViewer: {}, hideCompactToolbar: {}, showCompactToolbar: {},
            handleToolbarSwipe: { _ in }, selectSplitCard: { _ in },
            compactTransitionEnded: { _ in }
        )
        let window = mountBrowserSurface(safeAreaInsets: .zero, content: detail)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        XCTAssertNil(pages.activePage)
        XCTAssertFalse(pages.containsResidentPage(for: tab.id))

        // The same mounted detail must still restore an authorized tab.
        browser.updateSpaceAccessPolicy(.open, in: locked.id)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(pages.activePage?.tabID, tab.id)

        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: locked.id)
        pages.relockProtectedSpace(try XCTUnwrap(browser.selectedSpace))
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNil(pages.activePage)
        XCTAssertTrue(pages.containsResidentPage(for: tab.id))
        XCTAssertNil(firstWebHostView(in: window))
    }

    func testStartPageSearchUsesTheCorrectPresentationDestination() {
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

    func testColdLaunchCanActivateTheSelectedTabWithoutShowingTheTabViewer() {
        let navigation = MobileBrowserNavigationState(initiallyShowsCompactPage: true)

        navigation.adapt(to: .compact)

        XCTAssertTrue(navigation.compactShowsPage)
        XCTAssertTrue(navigation.compactPageIsFullyPresented)
        XCTAssertFalse(navigation.compactTabViewerChromeIsVisible)
        XCTAssertFalse(navigation.defersPageActivation)
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

    func testLegacyMobileBorderPreferenceMigratesOnceWithoutOverwritingNewChoice() {
        let suite = "app270-migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldKey = "crest.sidebar.collapsed.fullscreen.mobile"
        for enabled in [false, true] {
            defaults.removeObject(forKey: BrowserChromeAppearancePreference.borderlessKey)
            defaults.set(enabled, forKey: oldKey)
            BrowserChromeAppearancePreference.migrateLegacyMobilePreference(in: defaults)
            XCTAssertEqual(defaults.bool(forKey: BrowserChromeAppearancePreference.borderlessKey), enabled)
            XCTAssertNil(defaults.object(forKey: oldKey))
        }
        defaults.set(false, forKey: BrowserChromeAppearancePreference.borderlessKey)
        defaults.set(true, forKey: oldKey)
        BrowserChromeAppearancePreference.migrateLegacyMobilePreference(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: BrowserChromeAppearancePreference.borderlessKey))
    }

    func testSidebarSideChangesKeepTheMobilePageHostAndDocument() async throws {
        let space = makeSpace(index: 270)
        let page = MobileBrowserPage(tab: space.tabs[0], space: space, openNewTab: { _ in })
        page.webView.loadHTMLString(
            "<body style='height:4000px'><input id='draft' value='keep me'><script>window.documentToken='resident';</script></body>",
            baseURL: nil)
        for _ in 0..<100 {
            if !page.webView.isLoading, page.completedNavigationCount > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let controller = UIHostingController(rootView: MobileChromeContinuityShell(page: page, space: space))
        controller.additionalSafeAreaInsets.bottom = 24
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let originalHost = try XCTUnwrap(page.webView.superview)
        let navigationCount = page.completedNavigationCount
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            for right in [true, false] {
                controller.rootView = MobileChromeContinuityShell(
                    page: page, space: space, appearance: .init(sidebarOnRight: right, borderless: true),
                    direction: direction)
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                window.layoutIfNeeded()
                XCTAssertTrue(page.webView.superview === originalHost)
                XCTAssertEqual(page.completedNavigationCount, navigationCount)
                let state =
                    try await page.webView.evaluateJavaScript(
                        "[window.documentToken,document.querySelector('#draft').value]") as? [String]
                XCTAssertEqual(state, ["resident", "keep me"])
            }
        }
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
            BrowserCollapsedSidebarRevealMetrics.resolve(
                BrowserInteractionCapabilities(supportsTouch: true)
            ),
            .touch
        )
        XCTAssertEqual(
            BrowserCollapsedSidebarRevealMetrics.touch.width,
            26,
            "Only the extreme leading edge is reserved for revealing the sidebar; the rest of the page remains WebKit navigation territory."
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
            BrowserSidebarTabListMetrics.touch.sectionEndBandHeight,
            22
        )
    }

    func testEmojiCustomizationRoutesToTheFocusedNativeTextInput() {
        XCTAssertEqual(
            BrowserNativeEmojiPickerPresentation.current,
            .focusedTextInput
        )
    }

    func testMobileEmojiPickerUsesTheCompleteGeneratedCatalog() {
        let choices = BrowserTabEmojiChoices.matching(
            "",
            maximumVersion: 17
        )

        XCTAssertEqual(BrowserTabEmojiChoices.catalogMetadata.unicodeVersion, "17.0")
        XCTAssertEqual(choices.count, 3944)
        XCTAssertTrue(choices.contains { $0.emoji == "🫱🏿‍🫲🏻" })
        XCTAssertTrue(choices.contains { $0.emoji == "🫪" })
        XCTAssertTrue(
            choices.allSatisfy {
                BrowserIconSymbol.normalizedEmoji($0.emoji) == $0.emoji
            }
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

    func testAStaleMobileHostCannotReclaimOrMutateTheReplacementHostsWebView() {
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
        // SwiftUI may still issue updateUIView to the outgoing host while its
        // removal transition runs. Exercise that update before dismantling it.
        oldHost.configureViewport(
            MobileBrowserPageViewport(
                obscuresSystemSafeAreas: true,
                systemSafeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
                bottomChromeHeight: 100
            )
        )
        oldHost.attach(webView)
        XCTAssertTrue(webView.superview === newHost)
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

    // MARK: - Upward reveal routing

    func testUpwardRevealLandsOnThePlacementTheWindowAlreadyKeepsTheSidebarIn() {
        XCTAssertEqual(
            MobileCompactSidebarRevealPolicy.destination(
                sidebarPresentation: .docked
            ),
            .tabViewer,
            """
            A narrow phone's docked sidebar is the full-screen tab viewer, so \
            the swipe still lands exactly where it always has.
            """
        )
        XCTAssertEqual(
            MobileCompactSidebarRevealPolicy.destination(
                sidebarPresentation: .collapsed
            ),
            .floatingSidebar
        )
        XCTAssertEqual(
            MobileCompactSidebarRevealPolicy.destination(
                sidebarPresentation: .floating
            ),
            .floatingSidebar,
            """
            Already floating: the swipe re-asserts the placement rather than \
            promoting it to a viewer the window never asked for.
            """
        )
        XCTAssertEqual(
            Set(
                [BrowserSidebarPresentation.docked, .floating, .collapsed].map {
                    MobileCompactSidebarRevealPolicy.destination(
                        sidebarPresentation: $0
                    )
                }
            ),
            Set(MobileCompactSidebarRevealDestination.allCases),
            "Every destination is reachable from some placement."
        )
    }

    /// The undocked placements only ever have this toolbar to swipe because a
    /// split is on show, so the reveal must never be the thing that drops one.
    func testUpwardRevealNeverDropsTheSplitThatPutTheToolbarOnScreen() {
        for presentation in [BrowserSidebarPresentation.floating, .collapsed] {
            XCTAssertTrue(
                MobileSidebarPageFramePolicy.showsCompactToolbar(
                    sidebarPresentation: presentation,
                    presentsSplitView: true
                ),
                "A split is what puts the compact toolbar up when undocked."
            )
            XCTAssertFalse(
                MobileSidebarPageFramePolicy.showsCompactToolbar(
                    sidebarPresentation: presentation,
                    presentsSplitView: false
                ),
                "Without a split there is no undocked toolbar to swipe."
            )
            XCTAssertEqual(
                MobileCompactSidebarRevealPolicy.destination(
                    sidebarPresentation: presentation
                ),
                .floatingSidebar,
                """
                Landing on the viewer here would drop the split and re-dock the \
                sidebar in one move — two placement changes the finger never \
                asked for.
                """
            )
        }
    }

    func testRevealingTheFloatingSidebarKeepsTheCompactPageAndItsSplitOnScreen() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()
        navigation.hideRegularSidebar()

        XCTAssertEqual(
            MobileCompactSidebarRevealPolicy.destination(
                sidebarPresentation: navigation.regularSidebarPresentation
            ),
            .floatingSidebar
        )
        navigation.showRegularSidebar()

        XCTAssertEqual(navigation.regularSidebarPresentation, .floating)
        XCTAssertTrue(
            navigation.compactShowsPage,
            "The page — and the split composed on it — stays presented."
        )
    }

    func testRevealingFromADockedSidebarStillEntersTheFullScreenTabViewer() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .compact)
        navigation.selectTab()
        navigation.completePagePresentation()

        XCTAssertEqual(navigation.regularSidebarPresentation, .docked)
        XCTAssertEqual(
            MobileCompactSidebarRevealPolicy.destination(
                sidebarPresentation: navigation.regularSidebarPresentation
            ),
            .tabViewer
        )
        navigation.showTabViewer()

        XCTAssertFalse(navigation.compactShowsPage)
        XCTAssertEqual(navigation.regularSidebarPresentation, .docked)
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
            startupBehavior: .showStartPage,
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

    func testMobileDefaultZoomFollowsResidentAndRecreatedPages() throws {
        let preferences = BrowserDefaultPageZoomStore(
            persistence: InMemoryBrowserDefaultPageZoomPersistence(zoom: 1.25)
        )
        var space = makeSpace(index: 12)
        let backgroundTab = BrowserTab.startPage()
        space.tabs.append(backgroundTab)
        var session = BrowserSession(
            spaces: [space],
            selectedSpaceID: space.id
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true,
            pageZoomPreferences: preferences
        )

        pages.select(session: session)
        let page = try XCTUnwrap(pages.activePage)
        XCTAssertEqual(page.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(page.webView.pageZoom, 1.25, accuracy: 0.001)

        session.selectTab(backgroundTab.id)
        pages.select(session: session)
        let backgroundPage = try XCTUnwrap(pages.activePage)
        XCTAssertEqual(backgroundPage.pageZoom, 1.25, accuracy: 0.001)
        session.selectTab(page.tabID)
        pages.select(session: session)

        preferences.defaultZoom = 1.5
        XCTAssertEqual(page.pageZoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(
            backgroundPage.pageZoom,
            1.5,
            accuracy: 0.001,
            "Inactive resident pages must adopt the new global baseline."
        )

        pages.zoomIn()
        XCTAssertEqual(page.pageZoom, 1.75, accuracy: 0.001)
        page.load(try XCTUnwrap(URL(string: "about:blank#navigated")))
        XCTAssertEqual(
            page.pageZoom,
            1.75,
            accuracy: 0.001,
            "A page-local zoom override survives navigation in the same page."
        )

        preferences.defaultZoom = 2
        XCTAssertEqual(
            page.pageZoom,
            1.75,
            accuracy: 0.001,
            "Changing the baseline must not discard a temporary page override."
        )
        XCTAssertEqual(backgroundPage.pageZoom, 2, accuracy: 0.001)
        pages.resetZoom()
        XCTAssertEqual(page.pageZoom, 2, accuracy: 0.001)

        pages.zoomOut()
        XCTAssertEqual(page.pageZoom, 1.75, accuracy: 0.001)
        pages.unloadPage(for: page.tabID)
        pages.select(session: session)

        XCTAssertEqual(pages.activePage?.pageZoom ?? 0, 2, accuracy: 0.001)
        XCTAssertFalse(pages.activePage === page)
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
        let firstFocusRequest = page.findFocusRequest

        // Asking again while the bar is already up still asks for the field.
        page.presentFind()
        XCTAssertNotEqual(page.findFocusRequest, firstFocusRequest)

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

private struct MobileChromeContinuityShell: View {
    let page: MobileBrowserPage
    let space: BrowserSpace
    var appearance = BrowserChromeAppearance()
    var direction = LayoutDirection.leftToRight

    var body: some View {
        MobileRegularBrowserLayout(
            layout: MobileRegularWindowLayoutPolicy.resolve(availableWidth: 1200, preferredSidebarWidth: 320),
            sidebarPresentation: .docked, preferredSidebarWidth: .constant(320), reduceTransparency: true,
            layoutDirection: direction, space: space, showSidebar: {}, commitSidebarWidth: { _ in },
            sidebar: Color.clear,
            detail: MobileBrowserWebView(page: page)
                .padding(appearance.pageInsets(docked: true, direction: direction))
        )
        .environment(\.browserChromeAppearance, appearance)
        .transaction { $0.disablesAnimations = true }
        .environment(\.layoutDirection, direction)
    }
}
