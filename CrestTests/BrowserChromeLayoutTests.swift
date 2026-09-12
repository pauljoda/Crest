import AppKit
import SwiftUI
import WebKit
import XCTest

@testable import Crest

final class BrowserChromeLayoutTests: XCTestCase {

    @MainActor
    func testSetupActivationRejectsBrowserWithSetupPageTitle() {
        let browser = NSWindow()
        browser.identifier = NSUserInterfaceItemIdentifier(BrowserSceneID.browser.rawValue)
        browser.title = BrowserOnboardingWindowActivation.windowTitle
        XCTAssertFalse(BrowserOnboardingWindowActivation.isSetupWindow(browser))
        let setup = NSWindow()
        setup.identifier = NSUserInterfaceItemIdentifier(BrowserOnboardingCoordinator.sceneID)
        setup.title = ""
        XCTAssertTrue(BrowserOnboardingWindowActivation.isSetupWindow(setup))
    }

    func testSidebarDragAutoscrollOnlyRunsInsideTheVisibleEdgeBands() {
        let viewport = CGRect(x: 10, y: 100, width: 280, height: 500)

        XCTAssertLessThan(
            BrowserSidebarReorderPolicy.autoscrollStep(
                at: CGPoint(x: viewport.midX, y: viewport.minY + 1),
                in: viewport
            ),
            0
        )
        XCTAssertGreaterThan(
            BrowserSidebarReorderPolicy.autoscrollStep(
                at: CGPoint(x: viewport.midX, y: viewport.maxY - 1),
                in: viewport
            ),
            0
        )
        XCTAssertEqual(
            BrowserSidebarReorderPolicy.autoscrollStep(
                at: CGPoint(x: viewport.midX, y: viewport.midY),
                in: viewport
            ),
            0
        )
        XCTAssertEqual(
            BrowserSidebarReorderPolicy.autoscrollStep(
                at: CGPoint(x: viewport.maxX + 1, y: viewport.minY + 1),
                in: viewport
            ),
            0,
            "A pointer over fixed chrome must target that chrome, not keep "
                + "scrolling the list behind it."
        )
    }

    @MainActor
    func testSettingsPresentationKeepsTheLatestDestinationAndSpace() {
        let presentation = BrowserSpaceSettingsPresentationState()
        let first = SpaceID()
        let second = SpaceID()
        let firstAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: first,
            profileID: UUID()
        )
        let secondAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: second,
            profileID: UUID()
        )

        presentation.present(assignment: firstAssignment)
        presentation.present(.extensions, assignment: secondAssignment)

        XCTAssertEqual(presentation.requestedSpaceID, second)
        XCTAssertEqual(presentation.requestedAssignment, secondAssignment)
        XCTAssertEqual(presentation.requestedDestination, .extensions)
        XCTAssertEqual(presentation.revision, 2)
    }

    @MainActor
    func testRepeatedSettingsPresentationStillPublishesANewRequest() {
        let presentation = BrowserSpaceSettingsPresentationState()
        let spaceID = SpaceID()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: UUID()
        )

        presentation.present(.extensions, assignment: assignment)
        presentation.present(.extensions, assignment: assignment)

        XCTAssertEqual(presentation.requestedDestination, .extensions)
        XCTAssertEqual(presentation.requestedSpaceID, spaceID)
        XCTAssertEqual(presentation.revision, 2)
    }

    @MainActor
    func testSettingsPresentationRejectsAReplacementBrowsingProfile() throws {
        let browser = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let original = try XCTUnwrap(browser.selectedSpace)
        let presentation = BrowserSpaceSettingsPresentationState()
        presentation.present(
            assignment: BrowserSpaceRuntimeAssignment(space: original)
        )
        let replacement = BrowserSpace(
            id: original.id,
            profile: BrowsingProfile(),
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
        let index = try XCTUnwrap(
            browser.session.spaces.firstIndex { $0.id == original.id }
        )
        browser.session.spaces[index] = replacement

        XCTAssertNil(presentation.requestedSpaceID(in: browser))
    }

    @MainActor
    func testExtensionCommandSettingsPresentationTargetsShortcuts() throws {
        let presentation = BrowserSpaceSettingsPresentationState()
        let spaceID = SpaceID()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: UUID()
        )
        let route = try XCTUnwrap(
            BrowserExtensionCommandSettingsRoute(
                url: URL(
                    string: "chrome://extensions/configureCommands?command=eimadpbcbfnmbkopoojfekhnkhdbieeh-addSite"
                )!
            )
        )

        presentation.presentExtensionCommandSettings(
            route,
            assignment: assignment
        )

        XCTAssertEqual(presentation.requestedDestination, .shortcuts)
        XCTAssertEqual(presentation.requestedSpaceID, spaceID)
        XCTAssertEqual(presentation.requestedExtensionCommand, route)
        XCTAssertEqual(presentation.revision, 1)
    }

    func testChromeExtensionCommandURLRoutesToCrestShortcuts() throws {
        let route = try XCTUnwrap(
            BrowserExtensionCommandSettingsRoute(
                url: URL(
                    string: "chrome://extensions/configureCommands?command=eimadpbcbfnmbkopoojfekhnkhdbieeh-addSite"
                )!
            )
        )

        XCTAssertEqual(
            route.extensionID,
            "eimadpbcbfnmbkopoojfekhnkhdbieeh"
        )
        XCTAssertEqual(route.commandID, "addSite")
        XCTAssertNil(
            BrowserExtensionCommandSettingsRoute(
                url: URL(string: "https://example.com/extensions")!
            )
        )
    }

    func testWebExtensionShortcutKeysUseWebKitsSupportedCharacters() {
        XCTAssertEqual(
            BrowserExtensionShortcutPolicy.activationKey(
                for: .character("a")
            ),
            "a"
        )
        XCTAssertEqual(
            BrowserExtensionShortcutPolicy.activationKey(
                for: .special(.leftArrow)
            ),
            "\u{F702}"
        )
        XCTAssertNil(
            BrowserExtensionShortcutPolicy.activationKey(
                for: .special(.escape)
            )
        )
    }

    func testCertificateReviewRequiresHTTPSAndServerTrust() {
        XCTAssertTrue(
            BrowserSiteCertificatePresentationPolicy.isAvailable(
                url: URL(string: "https://example.com"),
                hasServerTrust: true
            )
        )
        XCTAssertFalse(
            BrowserSiteCertificatePresentationPolicy.isAvailable(
                url: URL(string: "http://example.com"),
                hasServerTrust: true
            )
        )
        XCTAssertFalse(
            BrowserSiteCertificatePresentationPolicy.isAvailable(
                url: URL(string: "https://example.com"),
                hasServerTrust: false
            )
        )
    }

    @MainActor
    func testExtensionPopupKeepsTheInvokingBrowserWindowAfterFocusChanges() {
        let browserWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let transientWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 292, height: 420),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let anchor = BrowserExtensionPopupAnchor(
            screenPoint: CGPoint(x: 176, y: 742),
            sourceWindow: browserWindow
        )

        XCTAssertTrue(
            anchor.contentView(fallbackWindow: transientWindow)
                === browserWindow.contentView
        )
    }

    @MainActor
    func testExtensionPopupStaysBoundToTheInvokingViewAfterWindowMoves()
        throws
    {
        let browserWindow = NSWindow(
            contentRect: CGRect(x: 40, y: 80, width: 1_200, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let iconView = NSView(
            frame: CGRect(x: 72, y: 710, width: 24, height: 24)
        )
        browserWindow.contentView?.addSubview(iconView)
        let anchor = BrowserExtensionPopupAnchor(sourceView: iconView)
            .offsetBy(dy: -18)

        browserWindow.setFrameOrigin(CGPoint(x: 320, y: 140))

        let source = try XCTUnwrap(
            anchor.presentationSource(fallbackWindow: nil)
        )
        XCTAssertTrue(source.view === iconView)
        XCTAssertEqual(source.rect, iconView.bounds)
    }

    func testSidebarClearHistoryKeepsTheInitiatingSpaceAfterSelectionChanges() throws {
        var session = BrowserSession.preview
        let initiatingSpace = try XCTUnwrap(session.selectedSpace)
        let laterSelectedSpace = try XCTUnwrap(
            session.spaces.first { $0.id != initiatingSpace.id }
        )
        let clearHistory = BrowserSidebarClearHistoryConfirmation(
            assignment: BrowserSpaceRuntimeAssignment(space: initiatingSpace),
            spaceName: initiatingSpace.name
        )

        session.selectSpace(laterSelectedSpace.id)

        XCTAssertEqual(session.selectedSpaceID, laterSelectedSpace.id)
        XCTAssertEqual(clearHistory.spaceID, initiatingSpace.id)
        XCTAssertEqual(clearHistory.spaceName, initiatingSpace.name)
    }

    func testStartupBehaviorDefaultsToShowingStartPage() {
        let suiteName = "BrowserChromeLayoutTests.startup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            BrowserStartupPreference.behavior(defaults: defaults),
            .showStartPage
        )

        defaults.set("showStartPage", forKey: BrowserStartupPreference.key)
        XCTAssertEqual(
            BrowserStartupPreference.behavior(defaults: defaults),
            .showStartPage
        )

        defaults.set(
            BrowserStartupBehavior.lastActiveTab.rawValue,
            forKey: BrowserStartupPreference.key
        )
        XCTAssertEqual(
            BrowserStartupPreference.behavior(defaults: defaults),
            .lastActiveTab
        )

        defaults.set("invalid", forKey: BrowserStartupPreference.key)
        XCTAssertEqual(
            BrowserStartupPreference.behavior(defaults: defaults),
            .showStartPage
        )

        XCTAssertFalse(BrowserStartupBehavior.showStartPage.activatesRestoredTab)
        XCTAssertTrue(BrowserStartupBehavior.lastActiveTab.activatesRestoredTab)
    }

    @MainActor
    func testWindowAccessibilityNamesAWindowThatDrawsItsOwnChrome() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        BrowserWindowAccessibility.pinTitle(
            BrowserOnboardingWindowActivation.windowTitle,
            on: window
        )

        XCTAssertTrue(
            window.styleMask.contains(.titled),
            "A borderless window carries no title, so it cannot be addressed by name."
        )
        XCTAssertEqual(window.title, "Crest Setup")
        XCTAssertEqual(window.accessibilityTitle(), "Crest Setup")
    }

    func testPeekKeyboardDismissalLeavesReturnToThePage() {
        XCTAssertEqual(
            BrowserPeekKeyboardPolicy.action(forKeyCode: 53, modifierFlags: []),
            .dismiss
        )
        XCTAssertNil(
            BrowserPeekKeyboardPolicy.action(forKeyCode: 36, modifierFlags: [])
        )
        XCTAssertNil(
            BrowserPeekKeyboardPolicy.action(forKeyCode: 76, modifierFlags: [])
        )
        XCTAssertNil(
            BrowserPeekKeyboardPolicy.action(
                forKeyCode: 36,
                modifierFlags: [.command]
            )
        )
    }

    func testSpaceAccessibilityReportsPositionAndMovesOnlyOneSpace() throws {
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
        XCTAssertNil(
            BrowserChromeAccessibility.adjacentSpaceID(
                spaces: session.spaces,
                selectedSpaceID: work.id,
                direction: .previous
            )
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

    func testChromeAccessibilityValuesPreserveTabFolderAndBadgeState() {
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
            BrowserChromeAccessibility.folderValue(isExpanded: false),
            "Collapsed"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.countValue(
                1,
                singular: "download",
                plural: "downloads"
            ),
            "1 download"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.countValue(
                2,
                singular: "archived tab",
                plural: "archived tabs"
            ),
            "2 archived tabs"
        )
    }

    func testSidebarResizeKeepsIntermediateWidthsInMemoryUntilCommit() {
        var transaction = BrowserSidebarWidthTransaction(persistedWidth: 289)

        transaction.resize(to: 302)
        transaction.resize(to: 318)
        transaction.resize(to: 341)

        XCTAssertEqual(transaction.width, 341)
        XCTAssertEqual(transaction.persistedWidth, 289)
        XCTAssertEqual(transaction.commit(), 341)
        XCTAssertEqual(transaction.persistedWidth, 341)
        XCTAssertNil(transaction.commit())
    }

    func testSidebarResizeClampsLiveAndRestoredWidths() {
        var transaction = BrowserSidebarWidthTransaction(persistedWidth: 120)

        XCTAssertEqual(transaction.width, BrowserChromeLayout.sidebarMinimumWidth)
        XCTAssertEqual(transaction.persistedWidth, BrowserChromeLayout.sidebarMinimumWidth)

        transaction.resize(to: 800)

        XCTAssertEqual(transaction.width, BrowserChromeLayout.sidebarMaximumWidth)
        XCTAssertEqual(transaction.commit(), BrowserChromeLayout.sidebarMaximumWidth)

        transaction.restore(persistedWidth: 300)

        XCTAssertEqual(transaction.width, 300)
        XCTAssertEqual(transaction.persistedWidth, 300)
    }

    func testLeadingEdgeRevealGestureMovesInwardInEitherLayoutDirection() {
        XCTAssertTrue(
            BrowserChromeDirectionPolicy.isLeadingEdgeReveal(
                CGSize(width: 52, height: 8),
                layoutDirection: .leftToRight
            )
        )
        XCTAssertTrue(
            BrowserChromeDirectionPolicy.isLeadingEdgeReveal(
                CGSize(width: -52, height: 8),
                layoutDirection: .rightToLeft
            )
        )
        XCTAssertFalse(
            BrowserChromeDirectionPolicy.isLeadingEdgeReveal(
                CGSize(width: 52, height: 8),
                layoutDirection: .rightToLeft
            )
        )
    }

    /// The shared direction source for the compact toolbar's horizontal swipe.
    ///
    /// What that swipe *does* is no longer this policy's business — on iOS it
    /// pages Split View cards, routed by `MobileToolbarSwipePolicy` — but "next"
    /// still has to mean the trailing neighbour in both writing directions, and
    /// this is the only place that decides it.
    func testHorizontalToolbarSwipeSemanticsMirrorInRightToLeftLayouts() {
        XCTAssertEqual(
            BrowserSpaceSwipePolicy.direction(
                for: CGSize(width: -90, height: 12),
                layoutDirection: .leftToRight
            ),
            .next
        )
        XCTAssertEqual(
            BrowserSpaceSwipePolicy.direction(
                for: CGSize(width: 90, height: 12),
                layoutDirection: .rightToLeft
            ),
            .next
        )
    }

    func testSidebarAuxiliaryMouseButtonsSwitchSpacesWithoutClaimingOtherButtons() {
        XCTAssertEqual(
            BrowserSidebarMouseButtonPolicy.action(for: 3),
            .previousSpace
        )
        XCTAssertEqual(
            BrowserSidebarMouseButtonPolicy.action(for: 4),
            .nextSpace
        )
        XCTAssertNil(BrowserSidebarMouseButtonPolicy.action(for: 0))
        XCTAssertNil(BrowserSidebarMouseButtonPolicy.action(for: 1))
        XCTAssertNil(BrowserSidebarMouseButtonPolicy.action(for: 2))
        XCTAssertNil(BrowserSidebarMouseButtonPolicy.action(for: 5))
    }

    func testAuxiliaryMouseButtonsStayWithinWebpageScope() {
        for action in [
            BrowserSidebarMouseButtonAction.previousSpace,
            .nextSpace,
        ] {
            XCTAssertEqual(
                BrowserSidebarMouseButtonPolicy.disposition(
                    for: action,
                    pointerScope: .webpage,
                    canNavigatePage: true
                ),
                .navigatePage(action)
            )
            XCTAssertEqual(
                BrowserSidebarMouseButtonPolicy.disposition(
                    for: action,
                    pointerScope: .webpage,
                    canNavigatePage: false
                ),
                .consume
            )
        }
    }

    func testAuxiliaryMouseButtonsStayWithinSidebarScope() {
        for action in [
            BrowserSidebarMouseButtonAction.previousSpace,
            .nextSpace,
        ] {
            XCTAssertEqual(
                BrowserSidebarMouseButtonPolicy.disposition(
                    for: action,
                    pointerScope: .sidebar,
                    canNavigatePage: true
                ),
                .switchSpace(action)
            )
            XCTAssertEqual(
                BrowserSidebarMouseButtonPolicy.disposition(
                    for: action,
                    pointerScope: .sidebar,
                    canNavigatePage: false
                ),
                .switchSpace(action)
            )
        }
    }

    func testAuxiliaryMouseButtonsRemainUnclaimedOutsidePageAndSidebar() {
        for action in [
            BrowserSidebarMouseButtonAction.previousSpace,
            .nextSpace,
        ] {
            XCTAssertNil(
                BrowserSidebarMouseButtonPolicy.disposition(
                    for: action,
                    pointerScope: .unowned,
                    canNavigatePage: true
                )
            )
        }
    }

    @MainActor
    func testOpenLocationRevealsTheSidebarAndPresentsTheCommandSurface() {
        let chrome = BrowserChromeState()
        chrome.hideSidebar()

        chrome.openLocation("https://example.com")

        XCTAssertEqual(chrome.columnVisibility, .all)
        XCTAssertEqual(
            chrome.commandPaletteMode,
            .editLocation("https://example.com")
        )
    }

    @MainActor
    func testRepeatedOpenLocationRequestsReplaceThePaletteQuery() {
        let chrome = BrowserChromeState()

        chrome.openLocation("https://example.com")
        chrome.openLocation("https://webkit.org")

        XCTAssertEqual(
            chrome.commandPaletteMode,
            .editLocation("https://webkit.org")
        )
    }

    @MainActor
    func testArchiveAndDownloadsPresentationIsExclusiveToItsOwningWindow() {
        let firstWindow = BrowserChromeState()
        let secondWindow = BrowserChromeState()

        firstWindow.utilityPresentation.present(.downloads)

        XCTAssertEqual(firstWindow.utilityPresentation.surface, .downloads)
        XCTAssertNil(secondWindow.utilityPresentation.surface)

        firstWindow.utilityPresentation.present(.archive)

        XCTAssertEqual(firstWindow.utilityPresentation.surface, .archive)
        XCTAssertNil(secondWindow.utilityPresentation.surface)

        firstWindow.utilityPresentation.dismiss(.downloads)
        XCTAssertEqual(
            firstWindow.utilityPresentation.surface,
            .archive,
            "A stale popover dismissal must not close the replacement Archive surface."
        )

        firstWindow.utilityPresentation.dismiss(.archive)
        XCTAssertNil(firstWindow.utilityPresentation.surface)
    }

    @MainActor
    func testMacChromeRestoresItsOwningWindowsSidebarPresentation() {
        let hiddenChrome = BrowserChromeState(sidebarIsPresented: false)
        let visibleChrome = BrowserChromeState(sidebarIsPresented: true)

        XCTAssertEqual(hiddenChrome.columnVisibility, .detailOnly)
        XCTAssertEqual(visibleChrome.columnVisibility, .all)
    }

}

extension BrowserChromeLayoutTests {
    @MainActor
    func testChromePreferencesPersistOnlyInTheirNamedIsolationDomain() {
        let id = "chrome-test-\(UUID().uuidString)"
        let environment = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1", "CREST_ISOLATED_PERSISTENCE_ID": id],
            isXCTestRuntime: false
        )
        let defaults = BrowserChromeAppearancePreference.defaults(for: environment)
        defer {
            defaults.removePersistentDomain(
                forName: BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(isolationID: id))
        }
        XCTAssertFalse(defaults.bool(forKey: BrowserChromeAppearancePreference.sidebarOnRightKey))
        XCTAssertFalse(defaults.bool(forKey: BrowserChromeAppearancePreference.borderlessKey))
        defaults.set(true, forKey: BrowserChromeAppearancePreference.sidebarOnRightKey)
        defaults.set(true, forKey: BrowserChromeAppearancePreference.borderlessKey)
        let restored = BrowserChromeAppearancePreference.defaults(for: environment)
        XCTAssertTrue(restored.bool(forKey: BrowserChromeAppearancePreference.sidebarOnRightKey))
        XCTAssertTrue(restored.bool(forKey: BrowserChromeAppearancePreference.borderlessKey))
        XCTAssertFalse(restored === UserDefaults.standard)
    }

    @MainActor
    func testWindowBorderMigratesAndKeepsDeviceLocalWidth() {
        let suite = "window-border-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for (legacyBorderless, expectedWidth) in [(true, 0.0), (false, 8.0)] {
            defaults.removeObject(forKey: BrowserChromeAppearancePreference.borderWidthKey)
            defaults.set(legacyBorderless, forKey: BrowserChromeAppearancePreference.borderlessKey)
            BrowserChromeAppearancePreference.migrateBorderWidth(in: defaults)
            XCTAssertEqual(defaults.double(forKey: BrowserChromeAppearancePreference.borderWidthKey), expectedWidth)
        }
        defaults.set(3.5, forKey: BrowserChromeAppearancePreference.borderWidthKey)
        defaults.set(true, forKey: BrowserChromeAppearancePreference.borderlessKey)
        BrowserChromeAppearancePreference.migrateBorderWidth(in: defaults)
        XCTAssertEqual(
            UserDefaults(suiteName: suite)!.double(forKey: BrowserChromeAppearancePreference.borderWidthKey), 3.5)

    }

    @MainActor
    func testChromeAppearanceChangesPreserveLivePageHostsAndDocumentState() async throws {
        for split in [false, true] {
            var space = BrowserRootPreviewFixture.space
            space.tabs = split ? BrowserRootPreviewFixture.splitMembers : [BrowserRootPreviewFixture.splitMembers[0]]
            for index in space.tabs.indices {
                space.tabs[index].url = URL(string: "about:blank")
                if !split { space.tabs[index].splitGroupID = nil }
            }
            space.selectedTabID = space.tabs[0].id
            let browser = BrowserStore(
                session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
                persistence: InMemoryBrowserSessionPersistence())
            let pages = BrowserPagePool()
            pages.select(session: browser.session)
            let model = BrowserRootModel(
                browser: browser, pages: pages, chrome: BrowserChromeState(sidebarIsPresented: true),
                spaceAccess: BrowserSpaceAccessController(), windowState: nil, startupBehavior: .showStartPage,
                persistedSidebarWidth: 289)
            let livePages = try space.tabs.map { tab in
                try XCTUnwrap(pages.surfacePage(for: tab, in: space, accessController: model.spaceAccess))
            }
            // Finish the pool's initial blank documents before starting this
            // navigation, so their late completion cannot contaminate the baseline.
            for _ in 0..<100 {
                if livePages.allSatisfy({ !$0.webView.isLoading && $0.completedNavigationCount > 0 }) { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            let initialCounts = livePages.map(\.completedNavigationCount)
            for page in livePages {
                page.setDeveloperToolbarVisible(true)
                page.webView.loadHTMLString(
                    "<body style='height:4000px'><input id='draft'><script>window.chromeIdentity=Math.random().toString(36);</script></body>",
                    baseURL: nil)
            }
            for _ in 0..<100 {
                if livePages.enumerated().allSatisfy({
                    !$0.element.webView.isLoading && $0.element.completedNavigationCount > initialCounts[$0.offset]
                }) {
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let host = NSHostingView(rootView: ChromeContinuityTestShell(model: model))
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            let parents = try livePages.map { try XCTUnwrap($0.webView.superview) }
            let navigationCounts = livePages.map(\.completedNavigationCount)
            var documentIDs: [String] = []
            for page in livePages {
                let identifier = try await page.webView.evaluateJavaScript(
                    "document.querySelector('#draft').value='unsaved';window.scrollTo(0,300);window.chromeIdentity")
                documentIDs.append(try XCTUnwrap(identifier as? String))
            }
            for appearance in [
                BrowserChromeAppearance(sidebarOnRight: true, borderless: true),
                .init(sidebarOnRight: false, borderless: true), .init(sidebarOnRight: true, borderless: false), .init(),
            ] {
                host.rootView = ChromeContinuityTestShell(model: model, appearance: appearance)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                XCTAssertEqual(browser.session.selectedSpaceID, space.id)
                XCTAssertEqual(browser.selectedTab?.id, space.selectedTabID)
                for (index, page) in livePages.enumerated() {
                    XCTAssertTrue(
                        page.webView.superview === parents[index], "A chrome change must not detach the live web view")
                    XCTAssertEqual(page.completedNavigationCount, navigationCounts[index])
                    let value =
                        try await page.webView.evaluateJavaScript(
                            "[window.chromeIdentity,document.querySelector('#draft').value,Math.round(scrollY)]")
                        as? [Any]
                    XCTAssertEqual(value?[0] as? String, documentIDs[index])
                    XCTAssertEqual(value?[1] as? String, "unsaved")
                    XCTAssertEqual(value?[2] as? Int, 300)
                }
            }
            if split {
                host.rootView = ChromeContinuityTestShell(
                    model: model, appearance: .init(sidebarOnRight: true, borderless: true))
                window.setContentSize(NSSize(width: 1000, height: 800))
                model.splitWidthTransactionBinding.wrappedValue = BrowserSplitWidthTransaction(
                    persistedFractions: [0.8, 0.2])
                for focusedIndex in [1, 0, 1] {
                    model.focusSplitCard(space.tabs[focusedIndex].id)
                    pages.select(session: browser.session)
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(300))
                    for (index, livePage) in livePages.enumerated() {
                        XCTAssertTrue(livePage.webView.superview === parents[index])
                        XCTAssertEqual(livePage.completedNavigationCount, navigationCounts[index])
                    }
                }
            }
        }
    }
}

private struct ChromeContinuityTestShell: View {
    let model: BrowserRootModel
    var appearance = BrowserChromeAppearance()
    @Namespace private var commandNamespace
    @Namespace private var tabNamespace
    var body: some View {
        BrowserRootShell(
            model: model, transientBrowsing: BrowserTransientBrowsingCoordinator(),
            spaceSettingsPresentation: BrowserSpaceSettingsPresentationState(), shortcuts: nil,
            storedSidebarWidth: .constant(289), appearance: appearance, windowTransparencyIsEnabled: false,
            windowTransparencyStrength: 0, commandSurfaceNamespace: commandNamespace,
            tabPromotionNamespace: tabNamespace)
    }
}
