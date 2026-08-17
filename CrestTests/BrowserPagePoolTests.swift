import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPagePoolTests: XCTestCase {
    func testCredentialAccessReconcilesAcrossAnExistingSpacePage() throws {
        var session = BrowserSession.preview
        let pool = BrowserPagePool()
        pool.select(session: session)
        XCTAssertTrue(try XCTUnwrap(pool.activePage).isCredentialAccessEnabled)

        let space = try XCTUnwrap(session.selectedSpace)
        var preferences = space.credentialPreferences
        preferences.isEnabled = false
        session.updateCredentialPreferences(preferences, in: space.id)
        pool.reconcileCredentialAccess(in: session)

        XCTAssertFalse(try XCTUnwrap(pool.activePage).isCredentialAccessEnabled)
        XCTAssertFalse(pool.downloadCenter.isCredentialAccessEnabled(in: space.id))
    }

    func testPerformanceProcessReporterFormatsOnlyValidWebContentPIDs() {
        XCTAssertNil(BrowserPerformanceProcessReporter.line(webContentPID: 0))
        XCTAssertNil(BrowserPerformanceProcessReporter.line(webContentPID: -1))
        XCTAssertEqual(
            BrowserPerformanceProcessReporter.line(webContentPID: 42),
            "CREST_PERFORMANCE_WEB_CONTENT_PID=42\n"
        )
    }

    func testSynchronizingAChangedSpaceActivatesItsSelectedPageImmediately() {
        var session = BrowserSession.preview
        let pool = BrowserPagePool()
        let workTabID = session.selectedTab?.id
        let personalSpaceID = session.spaces[1].id

        pool.select(session: session)
        session.selectSpace(personalSpaceID)
        pool.select(session: session)

        XCTAssertNotEqual(session.selectedTab?.id, workTabID)
        XCTAssertEqual(pool.activeTabID, session.selectedTab?.id)
        XCTAssertNotNil(pool.activePage)
    }

    func testDeactivatingDesktopPagePresentationRetainsAndRestoresItsPage() throws {
        let space = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        let session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let selectedTabID = try XCTUnwrap(session.selectedTab?.id)
        let pool = BrowserPagePool()

        pool.select(session: session)
        let originalPage = try XCTUnwrap(pool.activePage)

        pool.deactivatePagePresentation()

        XCTAssertNil(pool.activePage)
        XCTAssertTrue(pool.containsResidentPage(for: selectedTabID))

        pool.select(session: session)
        XCTAssertTrue(try XCTUnwrap(pool.activePage) === originalPage)
    }

    func testReloadRestoresTheSelectedPageWhenItsWebViewIsNotResident() throws {
        let tab = BrowserTab(
            title: "Restorable",
            url: try XCTUnwrap(URL(string: "about:blank")),
            placement: .current
        )
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let pool = BrowserPagePool()

        pool.reloadOrStop(in: session)

        XCTAssertEqual(pool.activeTabID, tab.id)
        XCTAssertTrue(pool.containsResidentPage(for: tab.id))
        XCTAssertNotNil(pool.activePage)
    }

    func testReloadFromOriginRestoresTheSelectedPageWhenItsWebViewIsNotResident() throws {
        let tab = BrowserTab(
            title: "Restorable",
            url: try XCTUnwrap(URL(string: "about:blank")),
            placement: .current
        )
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let pool = BrowserPagePool()

        pool.reloadFromOrigin(in: session)

        XCTAssertEqual(pool.activeTabID, tab.id)
        XCTAssertTrue(pool.containsResidentPage(for: tab.id))
        XCTAssertNotNil(pool.activePage)
    }

    func testReselectingAfterTransientPageAdoptionKeepsThePromotedPageActive() throws {
        let url = try XCTUnwrap(URL(string: "about:blank"))
        let sourceTab = BrowserTab(title: "Source", url: url, placement: .current)
        let space = makeSpace(tabs: [sourceTab], selectedTabID: sourceTab.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let pool = BrowserPagePool()
        let lease = try XCTUnwrap(
            pool.makeTransientPageLease(url: url, in: space)
        )
        let promotedPage = try XCTUnwrap(lease.page)
        let promotedTabID = try XCTUnwrap(
            session.openTab(
                title: "Promoted",
                url: url,
                in: space.id,
                shouldSelect: true
            )
        )
        let updatedSpace = try XCTUnwrap(session.space(id: space.id))

        XCTAssertTrue(
            pool.adoptTransientPage(
                lease,
                as: promotedTabID,
                in: updatedSpace
            )
        )
        pool.select(session: session)

        XCTAssertEqual(pool.activeTabID, promotedTabID)
        XCTAssertTrue(try XCTUnwrap(pool.activePage) === promotedPage)
    }

    func testTransientAdoptionRejectsAReplacementProfileWithTheSameSpaceID() throws {
        let url = try XCTUnwrap(URL(string: "about:blank"))
        let sourceTab = BrowserTab(title: "Source", url: url, placement: .current)
        let sourceSpace = makeSpace(
            tabs: [sourceTab],
            selectedTabID: sourceTab.id
        )
        let pool = BrowserPagePool(browsingMode: .privateBrowsing)
        let lease = try XCTUnwrap(
            pool.makeTransientPageLease(url: url, in: sourceSpace)
        )
        let promotedTab = BrowserTab(
            title: "Promoted",
            url: url,
            placement: .current
        )
        let replacementSpace = BrowserSpace(
            id: sourceSpace.id,
            profile: BrowsingProfile(),
            name: sourceSpace.name,
            symbol: sourceSpace.symbol,
            accent: sourceSpace.accent,
            branding: sourceSpace.branding,
            folders: sourceSpace.folders,
            tabs: sourceSpace.tabs + [promotedTab],
            archivedTabs: sourceSpace.archivedTabs,
            history: sourceSpace.history,
            browsingPreferences: sourceSpace.browsingPreferences,
            credentialPreferences: sourceSpace.credentialPreferences,
            accessPolicy: sourceSpace.accessPolicy,
            isSavedTabsExpanded: sourceSpace.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt:
                sourceSpace.savedTabsExpansionModifiedAt,
            selectedTabID: promotedTab.id
        )

        XCTAssertFalse(
            pool.adoptTransientPage(
                lease,
                as: promotedTab.id,
                in: replacementSpace
            )
        )
        XCTAssertNotNil(lease.page)
        XCTAssertEqual(lease.assignment.profileID, sourceSpace.profile.id)
    }

    func testTransientLeaseRestoresOnlyUntilItIsPermanentlyReleased() throws {
        let url = try XCTUnwrap(URL(string: "about:blank"))
        let tab = BrowserTab(title: "Transient", url: url, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(browsingMode: .privateBrowsing)
        let lease = try XCTUnwrap(
            pool.makeTransientPageLease(url: url, in: space)
        )

        lease.releaseForMemoryPressure()
        XCTAssertNil(lease.page)
        XCTAssertEqual(
            lease.assignment,
            BrowserSpaceRuntimeAssignment(space: space)
        )

        lease.restore()
        XCTAssertNotNil(lease.page)

        lease.release()
        lease.restore()
        XCTAssertNil(lease.page)
    }

    func testTransientLeaseDoesNotCrashWhenItsPagePoolHasBeenReleased() throws {
        let space = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        let url = try XCTUnwrap(URL(string: "about:blank"))
        var pool: BrowserPagePool? = BrowserPagePool()
        let lease = try XCTUnwrap(
            try XCTUnwrap(pool).makeTransientPageLease(
                url: url,
                in: space
            )
        )

        lease.releaseForMemoryPressure()
        weak let releasedPool = pool
        pool = nil

        XCTAssertNil(releasedPool)
        lease.restore()
        XCTAssertNil(lease.page)
        XCTAssertTrue(lease.wasReleasedForMemoryPressure)
    }

    func testDownloadOnlyTransientPageDismissesInsteadOfRemainingEmpty() async throws {
        let url = try XCTUnwrap(URL(string: "https://files.example/report.pdf"))
        let tab = BrowserTab(title: "Source", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()
        var dismissalCount = 0
        let lease = try XCTUnwrap(
            pool.makeTransientPageLease(
                url: url,
                in: space,
                onDownloadOnlyNavigation: { dismissalCount += 1 }
            )
        )
        let page = try XCTUnwrap(lease.page)

        page.discardDownloadOnlySurfaceIfNeeded()
        await Task.yield()

        XCTAssertEqual(dismissalCount, 1)
        XCTAssertNil(
            lease.page,
            "A transient page with no displayable response must not remain as an empty Peek."
        )
    }

    func testDownloadFromLoadedTransientPageKeepsItsExistingContent() async throws {
        let url = try XCTUnwrap(URL(string: "https://files.example/report.pdf"))
        let tab = BrowserTab(title: "Source", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()
        var dismissalCount = 0
        let lease = try XCTUnwrap(
            pool.makeTransientPageLease(
                url: url,
                in: space,
                onDownloadOnlyNavigation: { dismissalCount += 1 }
            )
        )
        let page = try XCTUnwrap(lease.page)
        page.webView(page.webView, didCommit: nil)

        page.discardDownloadOnlySurfaceIfNeeded()
        await Task.yield()

        XCTAssertEqual(dismissalCount, 0)
        XCTAssertNotNil(
            lease.page,
            "A download started from visible Peek content must leave that content in place."
        )
    }

    func testSpaceSwitchingKeepsPagesResidentUntilTheProtectedSpaceRelocks() throws {
        let firstTab = BrowserTab(title: "First", url: nil, placement: .current)
        let secondTab = BrowserTab(title: "Second", url: nil, placement: .current)
        let firstSpace = makeSpace(tabs: [firstTab], selectedTabID: firstTab.id)
        let secondSpace = makeSpace(tabs: [secondTab], selectedTabID: secondTab.id)
        var session = BrowserSession(
            spaces: [firstSpace, secondSpace],
            selectedSpaceID: firstSpace.id
        )
        let pool = BrowserPagePool()

        pool.select(session: session)
        let firstPage = try XCTUnwrap(pool.activePage)
        session.selectSpace(secondSpace.id)
        pool.select(session: session)

        XCTAssertTrue(pool.containsResidentPage(for: firstTab.id))
        XCTAssertTrue(pool.containsResidentPage(for: secondTab.id))

        session.selectSpace(firstSpace.id)
        pool.select(session: session)
        XCTAssertTrue(try XCTUnwrap(pool.activePage) === firstPage)

        pool.unloadPages(in: firstSpace.id)

        XCTAssertFalse(pool.containsResidentPage(for: firstTab.id))
        XCTAssertTrue(pool.containsResidentPage(for: secondTab.id))
    }

    func testReconcileReleasesClosedTabsAndClearsAClosedSelection() {
        let first = BrowserTab(title: "First", url: nil, placement: .current)
        let second = BrowserTab(title: "Second", url: nil, placement: .current)
        let space = makeSpace(tabs: [first, second], selectedTabID: first.id)
        let pool = BrowserPagePool()

        pool.select(tab: first, space: space)
        pool.select(tab: second, space: space)
        pool.reconcile(validTabIDs: [first.id])

        XCTAssertEqual(pool.retainedTabIDs, [first.id])
        XCTAssertNil(pool.activeTabID)
        XCTAssertNil(pool.activePage)
    }

    func testMovingATabAcrossSpacesRebuildsItWithTheDestinationProfile() throws {
        let tab = BrowserTab(title: "Movable", url: nil, placement: .current)
        let source = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let destinationStartPage = BrowserTab.startPage()
        let destination = makeSpace(
            tabs: [destinationStartPage],
            selectedTabID: destinationStartPage.id
        )
        var session = BrowserSession(spaces: [source, destination], selectedSpaceID: source.id)
        let pool = BrowserPagePool()

        pool.select(session: session)
        let sourcePage = try XCTUnwrap(pool.activePage)
        XCTAssertEqual(sourcePage.spaceID, source.id)

        XCTAssertTrue(
            session.moveTab(tab.id, from: source.id, into: destination.id)
        )
        pool.reconcile(session: session)
        XCTAssertFalse(pool.retainedTabIDs.contains(tab.id))

        pool.select(session: session)
        let destinationPage = try XCTUnwrap(pool.activePage)
        XCTAssertFalse(sourcePage === destinationPage)
        XCTAssertEqual(destinationPage.spaceID, destination.id)
        XCTAssertEqual(destinationPage.profileID, destination.profile.id)
    }

    func testEveryActivatedPageStaysResidentWithoutACountBasedLimit() {
        let first = BrowserTab(title: "First", url: nil, placement: .current)
        let second = BrowserTab(title: "Second", url: nil, placement: .current)
        let third = BrowserTab(title: "Third", url: nil, placement: .current)
        let space = makeSpace(tabs: [first, second, third], selectedTabID: first.id)
        let pool = BrowserPagePool()

        pool.select(tab: first, space: space)
        pool.select(tab: second, space: space)
        pool.select(tab: first, space: space)
        pool.select(tab: third, space: space)

        XCTAssertEqual(pool.retainedTabIDs, Set([first.id, second.id, third.id]))
        XCTAssertEqual(pool.activeTabID, third.id)
    }

    func testSwitchingTabsKeepsThePageResidentWithoutAnIdleTimer() {
        let reddit = BrowserTab(title: "Reddit", url: nil, placement: .current)
        let crest = BrowserTab(title: "Crest", url: nil, placement: .current)
        let space = makeSpace(
            tabs: [reddit, crest],
            selectedTabID: reddit.id
        )
        let pool = BrowserPagePool()
        let switchTime = Date(timeIntervalSince1970: 1_000)

        pool.select(tab: reddit, space: space, at: switchTime.addingTimeInterval(-1))
        pool.select(tab: crest, space: space, at: switchTime)

        XCTAssertTrue(pool.containsResidentPage(for: reddit.id))
        XCTAssertTrue(pool.containsResidentPage(for: crest.id))

        pool.select(tab: reddit, space: space, at: switchTime.addingTimeInterval(10 * 60))
        pool.select(tab: crest, space: space, at: switchTime.addingTimeInterval(10 * 60 + 1))

        XCTAssertTrue(pool.containsResidentPage(for: reddit.id))
        XCTAssertTrue(pool.containsResidentPage(for: crest.id))
    }

    func testSelectingASessionDoesNotForcePinnedSiblingsToLoad() {
        let firstPinned = BrowserTab(title: "First", url: nil, placement: .pinned)
        let secondPinned = BrowserTab(title: "Second", url: nil, placement: .pinned)
        let current = BrowserTab(title: "Current", url: nil, placement: .current)
        let space = makeSpace(
            tabs: [firstPinned, secondPinned, current],
            selectedTabID: current.id
        )
        let pool = BrowserPagePool()

        pool.select(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id)
        )

        XCTAssertEqual(pool.retainedTabIDs, [current.id])
    }

    func testBrowserPreparationOnlyLoadsTheRestoredTabWhenStartupOptsIn() async {
        let selected = BrowserTab(title: "Selected", url: nil, placement: .current)
        let space = makeSpace(tabs: [selected], selectedTabID: selected.id)
        let session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        for behavior in [
            BrowserStartupBehavior.waitForTabSelection,
            .lastActiveTab,
        ] {
            let browser = BrowserStore(
                session: session,
                persistence: InMemoryBrowserSessionPersistence()
            )
            let pages = BrowserPagePool(
                contentRuleListProvider: EmptyBrowserContentRuleListProvider()
            )
            let model = BrowserRootModel(
                browser: browser,
                pages: pages,
                chrome: BrowserChromeState(),
                spaceAccess: BrowserSpaceAccessController(),
                windowState: nil,
                startupBehavior: behavior,
                persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth
            )

            await model.prepareBrowser()

            XCTAssertEqual(
                pages.activeTabID,
                behavior.activatesRestoredTab ? selected.id : nil
            )
            XCTAssertEqual(
                pages.retainedTabIDs,
                behavior.activatesRestoredTab ? [selected.id] : []
            )
        }
    }

    func testUnloadingAPinnedPageReleasesOnlyItsResidentWebViewAndCanRehydrate() {
        let first = BrowserTab(title: "Pinned", url: nil, placement: .pinned)
        let second = BrowserTab(title: "Current", url: nil, placement: .current)
        let space = makeSpace(tabs: [first, second], selectedTabID: first.id)
        let pool = BrowserPagePool()

        pool.select(tab: first, space: space)
        pool.select(tab: second, space: space)
        XCTAssertTrue(pool.containsResidentPage(for: first.id))

        pool.unloadPage(for: first.id)

        XCTAssertFalse(pool.containsResidentPage(for: first.id))
        XCTAssertTrue(pool.containsResidentPage(for: second.id))
        XCTAssertEqual(pool.activeTabID, second.id)

        pool.select(tab: first, space: space)
        XCTAssertTrue(pool.containsResidentPage(for: first.id))
        XCTAssertEqual(pool.activeTabID, first.id)
    }

    func testCapturedUnloadRejectsAReplacementResidentPageAssignment() throws {
        let tab = BrowserTab(
            title: "Replacement resident",
            url: nil,
            placement: .pinned
        )
        let original = makeSpace(tabs: [tab], selectedTabID: tab.id)
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
        let pool = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        pool.select(tab: tab, space: replacement)

        XCTAssertFalse(
            pool.unloadPage(
                for: tab.id,
                matching: BrowserSpaceRuntimeAssignment(space: original)
            )
        )
        XCTAssertTrue(pool.containsResidentPage(for: tab.id))
        XCTAssertEqual(pool.activePage?.profileID, replacement.profile.id)
    }

    func testActivatingManyTabsDoesNotImposeAResidentPageCap() {
        let tabs = (1...13).map {
            BrowserTab(title: "Tab \($0)", url: nil, placement: .current)
        }
        let space = makeSpace(tabs: tabs, selectedTabID: tabs[0].id)
        let pool = BrowserPagePool()

        for tab in tabs {
            pool.select(tab: tab, space: space)
        }

        XCTAssertEqual(pool.retainedTabIDs, Set(tabs.map(\.id)))
        XCTAssertEqual(pool.activeTabID, tabs[12].id)

        pool.select(tab: tabs[0], space: space)

        XCTAssertEqual(pool.retainedTabIDs, Set(tabs.map(\.id)))
        XCTAssertEqual(pool.activeTabID, tabs[0].id)
    }

    func testPinnedPagesOnlyLoadWhenTheUserSelectsThem() {
        let firstPinned = BrowserTab(title: "First", url: nil, placement: .pinned)
        let secondPinned = BrowserTab(title: "Second", url: nil, placement: .pinned)
        let current = BrowserTab(title: "Current", url: nil, placement: .current)
        let space = makeSpace(
            tabs: [firstPinned, secondPinned, current],
            selectedTabID: current.id
        )
        let pool = BrowserPagePool()

        pool.select(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id)
        )

        XCTAssertTrue(pool.containsResidentPage(for: current.id))
        XCTAssertFalse(pool.containsResidentPage(for: firstPinned.id))
        XCTAssertFalse(pool.containsResidentPage(for: secondPinned.id))
        XCTAssertEqual(pool.retainedTabIDs.count, 1)

        pool.select(tab: secondPinned, space: space)

        XCTAssertTrue(pool.containsResidentPage(for: secondPinned.id))
        XCTAssertEqual(pool.activeTabID, secondPinned.id)
        XCTAssertEqual(pool.retainedTabIDs.count, 2)
    }

    func testSwitchingSpacesLoadsOnlyEachSpacesSelectedTab() throws {
        let spaces = (1...3).map { spaceIndex in
            let pins = (1...BrowserSpace.maximumPinnedTabs).map {
                BrowserTab(
                    title: "Space \(spaceIndex) pinned \($0)",
                    url: nil,
                    placement: .pinned
                )
            }
            let current = BrowserTab(
                title: "Space \(spaceIndex) current",
                url: nil,
                placement: .current
            )
            return makeSpace(
                tabs: pins + [current],
                selectedTabID: current.id
            )
        }
        var session = BrowserSession(
            spaces: spaces,
            selectedSpaceID: spaces[0].id
        )
        let pool = BrowserPagePool()

        for (index, space) in spaces.enumerated() {
            session.selectSpace(space.id)
            pool.select(session: session)
            XCTAssertEqual(pool.retainedTabIDs.count, index + 1)
            XCTAssertTrue(
                pool.containsResidentPage(for: try XCTUnwrap(space.selectedTabID))
            )
            XCTAssertTrue(
                space.pinnedTabs.allSatisfy {
                    !pool.containsResidentPage(for: $0.id)
                }
            )
        }

        for pin in spaces[2].pinnedTabs.reversed() {
            pool.select(tab: pin, space: spaces[2])
            XCTAssertEqual(pool.activeTabID, pin.id)
        }
        XCTAssertEqual(
            pool.retainedTabIDs.count,
            spaces.count + spaces[2].pinnedTabs.count
        )
    }

    func testWarningMemoryPressureUnloadsTheOldestInactiveTab() async {
        let tabs = (1...6).map {
            BrowserTab(title: "Tab \($0)", url: nil, placement: .current)
        }
        let space = makeSpace(tabs: tabs, selectedTabID: tabs[0].id)
        let pool = BrowserPagePool()

        for tab in tabs {
            pool.select(tab: tab, space: space)
        }

        pool.handleMemoryPressure(.warning)
        await pool.waitForPendingMemoryPressureResponse()

        XCTAssertFalse(pool.containsResidentPage(for: tabs[0].id))
        XCTAssertEqual(pool.retainedTabIDs.count, tabs.count - 1)
        XCTAssertEqual(pool.activeTabID, tabs[5].id)
    }

    func testMemoryPressureNeverUnloadsTheActivePage() async {
        let tab = BrowserTab(title: "Tab", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()

        pool.select(tab: tab, space: space)
        pool.handleMemoryPressure(.critical)
        await pool.waitForPendingMemoryPressureResponse()

        XCTAssertEqual(pool.retainedTabIDs, [tab.id])
        XCTAssertNotNil(pool.activePage)
    }

    func testManualKeepLoadedSkipsTheOldestTabUnderPressure() async {
        let kept = BrowserTab(
            title: "Kept",
            url: nil,
            placement: .saved,
            keepsPageLoaded: true
        )
        let eligible = BrowserTab(title: "Eligible", url: nil, placement: .saved)
        let active = BrowserTab(title: "Active", url: nil, placement: .current)
        let space = makeSpace(
            tabs: [kept, eligible, active],
            selectedTabID: active.id
        )
        let pool = BrowserPagePool()
        let start = Date(timeIntervalSince1970: 1_000)

        pool.select(tab: kept, space: space, at: start)
        pool.select(tab: eligible, space: space, at: start.addingTimeInterval(1))
        pool.select(tab: active, space: space, at: start.addingTimeInterval(2))
        pool.handleMemoryPressure(.warning)
        await pool.waitForPendingMemoryPressureResponse()

        XCTAssertTrue(pool.containsResidentPage(for: kept.id))
        XCTAssertFalse(pool.containsResidentPage(for: eligible.id))
        XCTAssertTrue(pool.containsResidentPage(for: active.id))
    }

    func testPlayingAndCapturingPagesStayResidentUnderCriticalPressure() async {
        let playing = BrowserTab(title: "Playing", url: nil, placement: .saved)
        let capturing = BrowserTab(title: "Capturing", url: nil, placement: .saved)
        let eligible = BrowserTab(title: "Eligible", url: nil, placement: .saved)
        let active = BrowserTab(title: "Active", url: nil, placement: .current)
        let space = makeSpace(
            tabs: [playing, capturing, eligible, active],
            selectedTabID: active.id
        )
        let protectedIDs = Set([playing.id, capturing.id])
        let pool = BrowserPagePool(
            residencyDecisionProvider: { page, isSelected in
                BrowserPageResidencyDecision(
                    isSelected: isSelected,
                    keepsPageLoaded: false,
                    isPlayingMedia: page.navigationContext.map {
                        $0.tabID == playing.id
                    } ?? false,
                    isCapturingMedia: page.navigationContext.map {
                        $0.tabID == capturing.id
                    } ?? false
                )
            }
        )

        for (index, tab) in space.tabs.enumerated() {
            pool.select(
                tab: tab,
                space: space,
                at: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        pool.handleMemoryPressure(.critical)
        await pool.waitForPendingMemoryPressureResponse()

        XCTAssertTrue(protectedIDs.allSatisfy(pool.containsResidentPage(for:)))
        XCTAssertFalse(pool.containsResidentPage(for: eligible.id))
        XCTAssertTrue(pool.containsResidentPage(for: active.id))
    }

    func testMemoryPressureReleasesTransientLeasesBeforeActiveTabPages() throws {
        let tab = BrowserTab(title: "Tab", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()
        let url = try XCTUnwrap(URL(string: "about:blank"))

        pool.select(tab: tab, space: space)
        let inactiveLease = try XCTUnwrap(
            pool.makeTransientPageLease(url: url, in: space)
        )
        inactiveLease.setActive(false)
        let activeLease = try XCTUnwrap(
            pool.makeTransientPageLease(url: url, in: space)
        )

        XCTAssertEqual(pool.retainedTransientPageCount, 2)
        pool.handleMemoryPressure(.warning)

        XCTAssertNil(inactiveLease.page)
        XCTAssertTrue(inactiveLease.wasReleasedForMemoryPressure)
        XCTAssertNotNil(activeLease.page)
        XCTAssertNotNil(pool.activePage)
        XCTAssertEqual(pool.retainedTransientPageCount, 1)

        pool.handleMemoryPressure(.critical)

        XCTAssertNil(activeLease.page)
        XCTAssertTrue(activeLease.wasReleasedForMemoryPressure)
        XCTAssertNotNil(pool.activePage)
        XCTAssertEqual(pool.retainedTransientPageCount, 0)

        inactiveLease.restore()
        XCTAssertNotNil(inactiveLease.page)
        XCTAssertFalse(inactiveLease.wasReleasedForMemoryPressure)
    }

    func testCriticalPressureEventReleasesTheActiveTransientLeaseAWarningKeeps() throws {
        let tab = BrowserTab(title: "Tab", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()
        let url = try XCTUnwrap(URL(string: "about:blank"))

        pool.select(tab: tab, space: space)
        let activeLease = try XCTUnwrap(
            pool.makeTransientPageLease(url: url, in: space)
        )
        // `dispatch_source_get_data` is only defined for the duration of the
        // event handler, so the level has to be captured there and passed in as a
        // value. Reading it back off the source after a hop is what made every
        // squeeze — critical included — arrive here as a warning.

        pool.handleMemoryPressureEvent([.warning])

        XCTAssertNotNil(
            activeLease.page,
            "A warning deliberately preserves the transient surface in use."
        )

        pool.handleMemoryPressureEvent([.critical])

        XCTAssertNil(
            activeLease.page,
            "Critical pressure must reach critical handling instead of collapsing to a warning."
        )
        XCTAssertTrue(activeLease.wasReleasedForMemoryPressure)
        XCTAssertNotNil(pool.activePage)
    }

    func testMemoryPressureUsesRecencyRatherThanTabPlacement() async {
        let pinned = (1...2).map {
            BrowserTab(title: "Pinned \($0)", url: nil, placement: .pinned)
        }
        let current = (1...3).map {
            BrowserTab(title: "Current \($0)", url: nil, placement: .current)
        }
        let space = makeSpace(
            tabs: pinned + current,
            selectedTabID: current[0].id
        )
        let pool = BrowserPagePool()

        for tab in pinned + current {
            pool.select(tab: tab, space: space)
        }
        XCTAssertEqual(pool.retainedTabIDs.count, 5)

        pool.handleMemoryPressure(.warning)
        await pool.waitForPendingMemoryPressureResponse()

        XCTAssertFalse(pool.containsResidentPage(for: pinned[0].id))
        XCTAssertTrue(pool.containsResidentPage(for: pinned[1].id))
        XCTAssertEqual(pool.activeTabID, current[2].id)
    }

    func testManualUnloadArchivesTheTabStateItTakesAway() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let stateful = BrowserTab(title: "Stateful", url: nil, placement: .current)
        let other = BrowserTab(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [stateful, other], selectedTabID: stateful.id)
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )
        let switchTime = Date(timeIntervalSince1970: 1_000)

        pool.select(tab: stateful, space: space, at: switchTime.addingTimeInterval(-1))
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.select(tab: other, space: space, at: switchTime)
        pool.unloadPage(for: stateful.id)
        await archive.flushPendingWrites()

        XCTAssertFalse(pool.containsResidentPage(for: stateful.id))
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profile.id, tabID: stateful.id),
            "Manual unloading must preserve the WebKit session state."
        )

        pool.reconcile(validTabIDs: [])
    }

    func testPrivateManualUnloadArchivesNothing() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let stateful = BrowserTab(title: "Stateful", url: nil, placement: .current)
        let other = BrowserTab(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [stateful, other], selectedTabID: stateful.id)
        let pool = BrowserPagePool(
            browsingMode: .privateBrowsing,
            tabStateArchive: archive
        )
        let switchTime = Date(timeIntervalSince1970: 1_000)

        pool.select(tab: stateful, space: space, at: switchTime.addingTimeInterval(-1))
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.select(tab: other, space: space, at: switchTime)
        pool.unloadPage(for: stateful.id)
        await archive.flushPendingWrites()

        XCTAssertFalse(pool.containsResidentPage(for: stateful.id))
        XCTAssertNil(
            archive.archivedState(profileID: space.profile.id, tabID: stateful.id),
            "A private page unloaded by hand must leave nothing behind."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: archive.rootDirectory.path),
            "A private pool must not create the archive during manual unloading."
        )
    }

    func testManualUnloadReleasesAnAdoptedPopupLikeAnyOtherResidentPage() async throws {
        let archive = try makeTabStateArchive()
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext(tabStateArchive: archive)
        let openerTabID = try XCTUnwrap(context.store.selectedSpace?.tabs.first?.id)

        _ = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )
        let popupTabID = try XCTUnwrap(context.pool.activeTabID)
        let popupPage = try XCTUnwrap(context.pool.activePage)
        context.store.selectTab(openerTabID)
        context.pool.select(session: context.store.session)
        XCTAssertTrue(context.pool.containsResidentPage(for: popupTabID))

        context.pool.unloadPage(for: popupTabID)
        await archive.flushPendingWrites()

        XCTAssertTrue(popupPage.wasOpenedAsPopup)
        XCTAssertFalse(
            context.pool.containsResidentPage(for: popupTabID),
            "An adopted popup follows the same explicit unload path as an ordinary tab."
        )
        XCTAssertEqual(context.pool.activeTabID, openerTabID)
        XCTAssertNil(
            archive.archivedState(
                profileID: popupPage.profileID,
                tabID: popupTabID
            ),
            "WebKit drives an adopted popup's window, so Crest never archives it."
        )

        context.pool.reconcile(validTabIDs: [])
    }

    func testPrivatePoolReusesOneEphemeralStorePerSpaceWithoutCredentialsOrExtensions() throws {
        let firstTab = BrowserTab.startPage()
        let secondTab = BrowserTab.startPage()
        let firstSpace = makeSpace(tabs: [firstTab], selectedTabID: firstTab.id)
        let secondSpace = makeSpace(tabs: [secondTab], selectedTabID: secondTab.id)
        let pool = BrowserPagePool(
            browsingMode: .privateBrowsing
        )

        pool.select(tab: firstTab, space: firstSpace)
        let firstPage = try XCTUnwrap(pool.activePage)
        let firstStore = firstPage.webView.configuration.websiteDataStore

        XCTAssertFalse(firstStore.isPersistent)
        XCTAssertNil(firstStore.identifier)
        XCTAssertNil(firstPage.webView.configuration.webExtensionController)
        XCTAssertEqual(
            firstPage.webView.configuration.userContentController.userScripts
                .map(\.source),
            [BrowserLinkContextContentBridge.source],
            """
            A private page carries the link-context bridge — it reports the link \
            under the cursor and stores nothing — and no credential or \
            extension script.
            """
        )

        pool.select(tab: secondTab, space: secondSpace)
        let secondStore = try XCTUnwrap(pool.activePage)
            .webView.configuration.websiteDataStore
        XCTAssertFalse(firstStore === secondStore)

        pool.select(tab: firstTab, space: firstSpace)
        let restoredFirstStore = try XCTUnwrap(pool.activePage)
            .webView.configuration.websiteDataStore
        XCTAssertTrue(firstStore === restoredFirstStore)
    }

    func testXCTestStandardPoolNeverUsesTheInstalledWebsiteDataStore() throws {
        let tab = BrowserTab.startPage()
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool()

        pool.select(tab: tab, space: space)
        let store = try XCTUnwrap(
            pool.activePage?.webView.configuration.websiteDataStore
        )

        XCTAssertFalse(store.isPersistent)
        XCTAssertNil(store.identifier)
    }

    func testClosingPrivatePoolReleasesEveryResidentPage() {
        let session = BrowserSession.privateBrowsing()
        let pool = BrowserPagePool(browsingMode: .privateBrowsing)
        pool.select(session: session)
        XCTAssertFalse(pool.retainedTabIDs.isEmpty)

        pool.closePrivateBrowsingSession(session)

        XCTAssertTrue(pool.retainedTabIDs.isEmpty)
        XCTAssertNil(pool.activePage)
        XCTAssertNil(pool.activeTabID)
    }

    func testDeletingASpacesRuntimeDataPreservesAnotherSpacesPageAndPermissions() async throws {
        let deletedTab = BrowserTab.startPage()
        let retainedTab = BrowserTab.startPage()
        let deletedSpace = makeSpace(
            tabs: [deletedTab],
            selectedTabID: deletedTab.id
        )
        let retainedSpace = makeSpace(
            tabs: [retainedTab],
            selectedTabID: retainedTab.id
        )
        let permissionCenter = BrowserSitePermissionCenter()
        let remover = RecordingWebsiteDataStoreRemover()
        let pool = BrowserPagePool(
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
        pool.select(tab: deletedTab, space: deletedSpace)
        pool.select(tab: retainedTab, space: retainedSpace)

        try await pool.deleteData(for: deletedSpace)

        XCTAssertFalse(pool.retainedTabIDs.contains(deletedTab.id))
        XCTAssertTrue(pool.retainedTabIDs.contains(retainedTab.id))
        XCTAssertEqual(pool.activeTabID, retainedTab.id)
        XCTAssertTrue(permissionCenter.records(in: deletedSpace.id).isEmpty)
        XCTAssertEqual(
            permissionCenter.records(in: retainedSpace.id).map(\.decision),
            [.denyPersistently]
        )
        XCTAssertEqual(remover.removedProfileIDs, [deletedSpace.profile.id])
    }

    func testDeletingSpaceThroughRegistryReleasesEveryWindowBeforeRemovingSharedDataOnce() async throws {
        let tab = BrowserTab.startPage()
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let remover = RecordingWebsiteDataStoreRemover()
        let primaryPool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            websiteDataStoreRemover: remover
        )
        let secondaryPool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            websiteDataStoreRemover: remover
        )
        let registry = BrowserPagePoolRegistry(primary: primaryPool)
        registry.register(secondaryPool)
        primaryPool.select(tab: tab, space: space)
        secondaryPool.select(tab: tab, space: space)

        try await registry.deleteData(for: space)

        XCTAssertFalse(primaryPool.retainedTabIDs.contains(tab.id))
        XCTAssertFalse(secondaryPool.retainedTabIDs.contains(tab.id))
        XCTAssertEqual(remover.removedProfileIDs, [space.profile.id])
    }

    func testRegistryResolvesAndUnregistersTheExactBrowserWindowRuntime() throws {
        let rootBrowser = BrowserStore.preview()
        let windowBrowser = rootBrowser.makeWindowStore()
        let pool = BrowserPagePool()
        let registry = BrowserPagePoolRegistry(primary: BrowserPagePool())
        let windowID = BrowserWindowID()

        registry.register(pool, browser: windowBrowser, for: windowID)

        let runtime = try XCTUnwrap(registry.runtime(for: windowID))
        XCTAssertTrue(runtime.browser === windowBrowser)
        XCTAssertTrue(runtime.pages === pool)

        registry.unregister(pool, for: windowID)
        XCTAssertNil(registry.runtime(for: windowID))
    }

    func testSpaceCannotRecreateItsPageWhileProfileDeletionIsSuspended() async throws {
        let tab = BrowserTab.startPage()
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let remover = SuspendingWebsiteDataStoreRemover()
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            websiteDataStoreRemover: remover
        )
        pool.select(tab: tab, space: space)
        XCTAssertNotNil(pool.activePage)
        let transientLease = try XCTUnwrap(
            pool.makeTransientPageLease(
                url: try XCTUnwrap(URL(string: "about:blank")),
                in: space
            )
        )

        let deletion = Task {
            try await pool.deleteData(for: space)
        }
        await remover.waitUntilRemovalStarts()

        pool.select(tab: tab, space: space)

        XCTAssertNil(pool.activePage)
        XCTAssertTrue(pool.retainedTabIDs.isEmpty)
        XCTAssertNil(transientLease.page)
        XCTAssertNil(
            pool.makeTransientPageLease(
                url: try XCTUnwrap(URL(string: "about:blank")),
                in: space
            )
        )
        transientLease.restore()
        XCTAssertNil(transientLease.page)

        remover.finishRemoval()
        try await deletion.value
    }

    func testPoolRoutesAcceptedHTTPAuthenticationBackToTheExactSpaceStore() async throws {
        let tab = BrowserTab(title: "Protected", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let protectionSpace = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 443,
            protocol: "https",
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let credentialProtectionSpace = try XCTUnwrap(
            BrowserHTTPAuthenticationProtectionSpace(protectionSpace)
        )
        let storedCredential = BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: space.id,
                origin: credentialProtectionSpace.origin,
                scope: credentialProtectionSpace.credentialScope,
                username: "member"
            ),
            password: "stored-secret"
        )
        var savedRequests: [(BrowserHTTPAuthenticationSaveRequest, SpaceID)] = []
        let saved = expectation(description: "Accepted credential is marked used")
        let pool = BrowserPagePool(
            loadHTTPAuthenticationCredential: { requestedProtectionSpace, spaceID in
                XCTAssertEqual(spaceID, space.id)
                XCTAssertEqual(requestedProtectionSpace, credentialProtectionSpace)
                return storedCredential
            },
            saveHTTPAuthenticationCredential: { request, spaceID in
                savedRequests.append((request, spaceID))
                saved.fulfill()
            }
        )
        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: PagePoolAuthenticationChallengeSenderStub()
        )

        let resolution = await withCheckedContinuation { continuation in
            page.webView(page.webView, didReceive: challenge) { disposition, credential in
                continuation.resume(returning: (disposition, credential))
            }
        }

        XCTAssertEqual(resolution.0, .useCredential)
        XCTAssertEqual(resolution.1?.user, "member")
        XCTAssertEqual(resolution.1?.password, "stored-secret")
        XCTAssertTrue(savedRequests.isEmpty)

        page.webView(page.webView, didFinish: nil)
        await fulfillment(of: [saved], timeout: 1)

        XCTAssertEqual(savedRequests.count, 1)
        XCTAssertEqual(savedRequests.first?.0.replacing, storedCredential.descriptor)
        XCTAssertEqual(savedRequests.first?.1, space.id)
    }

    func testUserActivatedPopupAdoptsWebKitsConfigurationIntoANewSelectedTab() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.selectedTab?.id)

        let popupWebView = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        let popupTab = try XCTUnwrap(
            context.store.selectedSpace?.tabs.first { $0.id != openerTabID }
        )
        XCTAssertEqual(popupTab.url, popupURL)
        XCTAssertEqual(context.store.selectedTab?.id, popupTab.id)
        XCTAssertEqual(context.pool.activeTabID, popupTab.id)
        XCTAssertTrue(context.pool.containsResidentPage(for: popupTab.id))
        XCTAssertTrue(
            popupWebView.configuration.userContentController
                === context.opener.webView.configuration.userContentController
        )
    }

    func testAdoptedPopupWebViewIsTheOneRegisteredForItsPopupTab() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()

        let popupWebView = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        let popupPage = try XCTUnwrap(context.pool.activePage)
        XCTAssertTrue(popupPage.webView === popupWebView)
        XCTAssertTrue(popupPage.wasOpenedAsPopup)
        XCTAssertFalse(context.opener.wasOpenedAsPopup)
    }

    func testAdoptedPopupInheritsTheOpenerWebsiteDataStoreAndProfile() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()

        let popupWebView = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        let popupPage = try XCTUnwrap(context.pool.activePage)
        XCTAssertTrue(
            popupWebView.configuration.websiteDataStore
                === context.opener.webView.configuration.websiteDataStore
        )
        XCTAssertEqual(popupPage.spaceID, context.opener.spaceID)
        XCTAssertEqual(popupPage.profileID, context.opener.profileID)
    }

    func testSelectingAnAdoptedPopupTabLeavesItsFirstNavigationToWebKit() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()

        _ = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )
        let popupPage = try XCTUnwrap(context.pool.activePage)
        context.pool.select(session: context.store.session)

        XCTAssertTrue(context.pool.activePage === popupPage)
        XCTAssertTrue(popupPage.isAwaitingPopupNavigation)
        XCTAssertNil(popupPage.pendingNavigationURL)
    }

    func testPopupWithoutARequestedURLAdoptsABlankTab() throws {
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.selectedTab?.id)

        _ = try XCTUnwrap(context.requestPopup(url: nil, navigationType: .linkActivated))

        let popupTab = try XCTUnwrap(
            context.store.selectedSpace?.tabs.first { $0.id != openerTabID }
        )
        XCTAssertEqual(popupTab.url, URL(string: "about:blank"))
        XCTAssertFalse(popupTab.isStartPage)
    }

    func testPopupFromATransientPeekPageFallsBackToARoutedTab() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let peekURL = try XCTUnwrap(URL(string: "about:blank"))
        var routedURLs: [URL] = []
        let openerTab = BrowserTab(title: "Opener", url: nil, placement: .current)
        let space = makeSpace(tabs: [openerTab], selectedTabID: openerTab.id)
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pool = BrowserPagePool(
            popupTabHost: store.popupTabHost,
            openNewTab: { routedURLs.append($0) }
        )
        let lease = try XCTUnwrap(
            pool.makeTransientPageLease(url: peekURL, in: space)
        )
        let peekPage = try XCTUnwrap(lease.page)
        let tabCount = try XCTUnwrap(store.selectedSpace?.tabs.count)

        let popupWebView = peekPage.webView(
            peekPage.webView,
            createWebViewWith: try XCTUnwrap(
                peekPage.webView.configuration.copy() as? WKWebViewConfiguration
            ),
            for: StubPopupNavigationAction(url: popupURL, navigationType: .linkActivated),
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(popupWebView)
        XCTAssertEqual(routedURLs, [popupURL])
        XCTAssertEqual(store.selectedSpace?.tabs.count, tabCount)
    }

    func testClosingAnAdoptedPopupWebViewClosesItsTab() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.selectedTab?.id)

        _ = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )
        let popupPage = try XCTUnwrap(context.pool.activePage)
        let popupTabID = try XCTUnwrap(context.pool.activeTabID)

        popupPage.webViewDidClose(popupPage.webView)

        XCTAssertFalse(
            context.store.selectedSpace?.tabs.contains { $0.id == popupTabID } == true
        )
        XCTAssertEqual(
            context.store.selectedSpace?.archivedTabs.last?.tab.id,
            popupTabID
        )
        XCTAssertEqual(context.store.selectedTab?.id, openerTabID)
    }

    func testClosingAPageTheUserOpenedKeepsItsTab() throws {
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.selectedTab?.id)

        context.opener.webViewDidClose(context.opener.webView)

        XCTAssertEqual(context.store.selectedTab?.id, openerTabID)
        XCTAssertTrue(
            context.store.selectedSpace?.tabs.contains { $0.id == openerTabID } == true
        )
    }

    func testPrivatePopupAdoptionStaysInsideThePrivatePool() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let regular = try makePopupContext()
        let privateContext = try makePopupContext(browsingMode: .privateBrowsing)

        let popupWebView = try XCTUnwrap(
            privateContext.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        XCTAssertFalse(popupWebView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(privateContext.store.selectedSpace?.tabs.count, 2)
        XCTAssertEqual(regular.store.selectedSpace?.tabs.count, 1)
        XCTAssertFalse(regular.pool.activePage?.wasOpenedAsPopup == true)
        XCTAssertTrue(
            privateContext.pool.activePage?.wasOpenedAsPopup == true
        )
    }

    // MARK: - Split View presented set

    func testSelectingASplitMemberPresentsEveryMemberInSessionOrder() throws {
        let groupID = SplitGroupID()
        let members = try (1...3).map { index in
            BrowserTab(
                title: "Member \(index)",
                url: try XCTUnwrap(URL(string: "https://split.crest.test/\(index)")),
                placement: .current,
                splitGroupID: groupID
            )
        }
        let outsider = BrowserTab(title: "Outsider", url: nil, placement: .current)
        let space = makeSpace(
            tabs: members + [outsider],
            selectedTabID: members[1].id
        )
        let pool = BrowserPagePool()

        pool.select(tab: members[1], space: space)

        XCTAssertEqual(pool.presentedTabIDs, members.map(\.id))
        XCTAssertEqual(pool.activeTabID, members[1].id)
        XCTAssertEqual(pool.retainedTabIDs, Set(members.map(\.id)))
        for member in members {
            let page = try XCTUnwrap(pool.presentedPage(for: member.id))
            XCTAssertEqual(
                page.pendingNavigationURL ?? page.webView.url,
                member.url,
                "A card the person can see must not wait for focus to load."
            )
        }
        XCTAssertTrue(
            try XCTUnwrap(pool.activePage)
                === pool.presentedPage(for: members[1].id),
            "The focused card is the active page."
        )
        XCTAssertNil(
            pool.presentedPage(for: outsider.id),
            "A tab outside the group is not a card."
        )

        pool.reconcile(validTabIDs: [])
    }

    func testAnUngroupedSelectionPresentsOnlyItself() {
        let solitary = BrowserTab(
            title: "Solitary",
            url: nil,
            placement: .current,
            splitGroupID: SplitGroupID()
        )
        let plain = BrowserTab(title: "Plain", url: nil, placement: .current)
        let space = makeSpace(tabs: [solitary, plain], selectedTabID: plain.id)
        let pool = BrowserPagePool()

        pool.select(tab: plain, space: space)

        XCTAssertEqual(pool.presentedTabIDs, [plain.id])
        XCTAssertNil(pool.presentedPage(for: solitary.id))

        pool.select(tab: solitary, space: space)

        XCTAssertEqual(
            pool.presentedTabIDs,
            [solitary.id],
            "A group of one renders as a plain tab until its siblings arrive."
        )
        XCTAssertNil(pool.presentedPage(for: plain.id))
        XCTAssertEqual(pool.retainedTabIDs, Set([plain.id, solitary.id]))
    }

    func testPressureSparesEveryPresentedMemberUntilItLeavesTheScreen() async {
        let groupID = SplitGroupID()
        let first = BrowserTab(
            title: "First member",
            url: nil,
            placement: .current,
            splitGroupID: groupID
        )
        let second = BrowserTab(
            title: "Second member",
            url: nil,
            placement: .current,
            splitGroupID: groupID
        )
        let background = BrowserTab(
            title: "Background",
            url: nil,
            placement: .current
        )
        let space = makeSpace(
            tabs: [first, second, background],
            selectedTabID: second.id
        )
        let pool = BrowserPagePool()
        let start = Date(timeIntervalSince1970: 1_000)

        pool.select(tab: background, space: space, at: start)
        pool.select(tab: second, space: space, at: start.addingTimeInterval(1))
        pool.handleMemoryPressure(.critical, at: start.addingTimeInterval(2))
        await pool.waitForPendingMemoryPressureResponse()

        XCTAssertTrue(
            pool.containsResidentPage(for: first.id),
            "An unfocused card is still on screen, so it is not a saving to make."
        )
        XCTAssertTrue(pool.containsResidentPage(for: second.id))
        XCTAssertFalse(pool.containsResidentPage(for: background.id))

        pool.select(tab: background, space: space, at: start.addingTimeInterval(3))
        XCTAssertEqual(pool.presentedTabIDs, [background.id])

        // One squeeze releases half of what is eligible, so both former members
        // need two of them.
        for squeeze in 0..<2 {
            pool.handleMemoryPressure(
                .critical,
                at: start.addingTimeInterval(TimeInterval(120 + squeeze * 2))
            )
            await pool.waitForPendingMemoryPressureResponse()
        }

        XCTAssertFalse(
            pool.containsResidentPage(for: first.id),
            "A member that left the screen is stamped inactive and evictable."
        )
        XCTAssertFalse(pool.containsResidentPage(for: second.id))
        XCTAssertTrue(pool.containsResidentPage(for: background.id))
    }

    func testReconcilePrunesClosedMembersFromThePresentedSet() {
        let groupID = SplitGroupID()
        let members = (1...3).map { index in
            BrowserTab(
                title: "Member \(index)",
                url: nil,
                placement: .current,
                splitGroupID: groupID
            )
        }
        let space = makeSpace(tabs: members, selectedTabID: members[0].id)
        let pool = BrowserPagePool()

        pool.select(tab: members[0], space: space)
        pool.reconcile(validTabIDs: Set(members.dropLast().map(\.id)))

        XCTAssertEqual(pool.presentedTabIDs, members.dropLast().map(\.id))
        XCTAssertEqual(pool.activeTabID, members[0].id)
        XCTAssertFalse(pool.containsResidentPage(for: members[2].id))

        pool.reconcile(validTabIDs: [])

        XCTAssertTrue(pool.presentedTabIDs.isEmpty)
        XCTAssertNil(pool.activeTabID)
    }

    func testDeactivatingPresentationDropsEveryCardAndStampsThemAllInactive() async {
        let groupID = SplitGroupID()
        let first = BrowserTab(
            title: "First member",
            url: nil,
            placement: .current,
            splitGroupID: groupID
        )
        let second = BrowserTab(
            title: "Second member",
            url: nil,
            placement: .current,
            splitGroupID: groupID
        )
        let space = makeSpace(tabs: [first, second], selectedTabID: first.id)
        let pool = BrowserPagePool()
        let start = Date(timeIntervalSince1970: 1_000)

        pool.select(tab: first, space: space, at: start)
        XCTAssertEqual(pool.presentedTabIDs, [first.id, second.id])

        pool.deactivatePagePresentation(at: start.addingTimeInterval(1))

        XCTAssertTrue(pool.presentedTabIDs.isEmpty)
        XCTAssertNil(pool.activeTabID)
        XCTAssertNil(pool.activePage)
        XCTAssertNil(pool.presentedPage(for: second.id))
        XCTAssertEqual(
            pool.retainedTabIDs,
            Set([first.id, second.id]),
            "Deactivation hides the cards without evicting their runtimes."
        )

        // Every card was stamped on the way out, so pressure can now reclaim
        // the unfocused member as readily as the focused one.
        for squeeze in 0..<2 {
            pool.handleMemoryPressure(
                .critical,
                at: start.addingTimeInterval(TimeInterval(120 + squeeze * 2))
            )
            await pool.waitForPendingMemoryPressureResponse()
        }

        XCTAssertTrue(pool.retainedTabIDs.isEmpty)
    }

    func testRelockingASpaceDropsEveryCardOfAnOpenSplit() {
        let groupID = SplitGroupID()
        let first = BrowserTab(
            title: "First secret",
            url: nil,
            placement: .current,
            splitGroupID: groupID
        )
        let second = BrowserTab(
            title: "Second secret",
            url: nil,
            placement: .current,
            splitGroupID: groupID
        )
        let protectedSpace = makeSpace(
            tabs: [first, second],
            selectedTabID: first.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = BrowserTab(title: "Open", url: nil, placement: .current)
        let openSpace = makeSpace(tabs: [openTab], selectedTabID: openTab.id)
        let pool = BrowserPagePool()

        pool.select(tab: openTab, space: openSpace)
        pool.select(tab: first, space: protectedSpace)
        XCTAssertEqual(pool.presentedTabIDs, [first.id, second.id])

        pool.relockProtectedSpace(protectedSpace)

        XCTAssertTrue(
            pool.presentedTabIDs.isEmpty,
            "Locking a Space must take every card away, not just the focused one."
        )
        XCTAssertNil(pool.activeTabID)
        XCTAssertFalse(pool.containsResidentPage(for: first.id))
        XCTAssertFalse(pool.containsResidentPage(for: second.id))
        XCTAssertTrue(pool.containsResidentPage(for: openTab.id))
    }

    func testAdoptingAPopupKeepsItsCardUntilTheStoreReselects() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.selectedTab?.id)

        _ = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )
        let popupTabID = try XCTUnwrap(context.pool.activeTabID)

        XCTAssertEqual(
            context.pool.presentedTabIDs,
            [openerTabID, popupTabID],
            "Adoption focuses the popup a frame before selection settles, so its card exists at once."
        )
        XCTAssertNotNil(context.pool.presentedPage(for: popupTabID))

        context.pool.select(session: context.store.session)

        XCTAssertEqual(context.pool.presentedTabIDs, [popupTabID])
        XCTAssertNil(context.pool.presentedPage(for: openerTabID))
    }

    // MARK: - Archived tab state

    func testManualUnloadingATabArchivesItsSessionStateAndReselectingRestoresIt() async throws {
        let archive = try makeTabStateArchive()
        let firstURL = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        var stateful = BrowserTab(title: "Stateful", url: nil, placement: .current)
        let other = BrowserTab(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [stateful, other], selectedTabID: stateful.id)
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pool.select(tab: stateful, space: space)
        let originalPage = try XCTUnwrap(pool.activePage)
        try await load(firstURL, in: originalPage)
        try await load(secondURL, in: originalPage)
        XCTAssertTrue(originalPage.webView.canGoBack)
        // The store keeps a tab's URL in step with its page, so the test does the
        // same before the page is taken away.
        stateful.url = secondURL

        pool.select(tab: other, space: space)
        pool.unloadPage(for: stateful.id)
        XCTAssertFalse(pool.containsResidentPage(for: stateful.id))
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profile.id, tabID: stateful.id)
        )

        pool.select(tab: stateful, space: space)
        let restoredPage = try XCTUnwrap(pool.activePage)

        XCTAssertFalse(restoredPage === originalPage)
        XCTAssertEqual(restoredPage.webView.url, secondURL)
        XCTAssertTrue(
            restoredPage.webView.canGoBack,
            "A restored tab must come back with the back/forward list it had."
        )
        XCTAssertEqual(
            restoredPage.webView.backForwardList.backList.map(\.url),
            [firstURL]
        )

        pool.reconcile(validTabIDs: [])
    }

    func testAFreshPoolOnTheSameArchiveRestoresWhatTheOldPoolLeft() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        var stateful = BrowserTab(title: "Stateful", url: nil, placement: .current)
        let space = makeSpace(tabs: [stateful], selectedTabID: stateful.id)
        let firstLaunch = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        firstLaunch.select(tab: stateful, space: space)
        let page = try XCTUnwrap(firstLaunch.activePage)
        try await load(url, in: page)
        try await load(secondURL, in: page)
        stateful.url = secondURL
        // What a scene resigning active does, rather than an eviction.
        firstLaunch.archiveResidentTabStates()
        await firstLaunch.flushPendingTabStateWrites()
        firstLaunch.reconcile(validTabIDs: [])

        let secondLaunch = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )
        secondLaunch.select(tab: stateful, space: space)
        let restoredPage = try XCTUnwrap(secondLaunch.activePage)

        XCTAssertEqual(restoredPage.webView.url, secondURL)
        XCTAssertEqual(
            restoredPage.webView.backForwardList.backList.map(\.url),
            [url]
        )

        secondLaunch.reconcile(validTabIDs: [])
    }

    func testUnloadingATabArchivesItsSessionState() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Unloadable", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pool.select(tab: tab, space: space)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.unloadPage(for: tab.id)
        await archive.flushPendingWrites()

        XCTAssertFalse(pool.containsResidentPage(for: tab.id))
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profile.id, tabID: tab.id)
        )
    }

    func testStateWebKitRefusesFallsBackToAnOrdinaryLoad() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Corrupt", url: url, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        // Correctly framed and stamped for this build, so only WebKit can refuse it.
        archive.archive(
            interactionState: Data((0..<1024).map { _ in UInt8.random(in: 0...255) }),
            url: url,
            profileID: space.profile.id,
            tabID: tab.id
        )
        await archive.flushPendingWrites()
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pool.select(tab: tab, space: space)
        let page = try XCTUnwrap(pool.activePage)

        XCTAssertTrue(page.webView.backForwardList.backList.isEmpty)
        XCTAssertEqual(
            page.pendingNavigationURL ?? page.webView.url,
            url,
            "Refused state must leave a plain load of the tab's own URL behind."
        )

        pool.reconcile(validTabIDs: [])
    }

    func testStateForADifferentDestinationIsIgnoredInFavourOfTheTabURL() async throws {
        let archive = try makeTabStateArchive()
        let archivedURL = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let renamedURL = try XCTUnwrap(URL(string: "https://state.crest.test/somewhere-else"))
        var stateful = BrowserTab(title: "Renamed", url: nil, placement: .current)
        let other = BrowserTab(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [stateful, other], selectedTabID: stateful.id)
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pool.select(tab: stateful, space: space)
        try await load(archivedURL, in: try XCTUnwrap(pool.activePage))
        pool.select(tab: other, space: space)
        pool.unloadPage(for: stateful.id)
        await archive.flushPendingWrites()

        // The tab was pointed somewhere else while it had no web view.
        stateful.url = renamedURL
        pool.select(tab: stateful, space: space)
        let page = try XCTUnwrap(pool.activePage)

        XCTAssertTrue(page.webView.backForwardList.backList.isEmpty)
        XCTAssertEqual(page.pendingNavigationURL ?? page.webView.url, renamedURL)

        pool.reconcile(validTabIDs: [])
    }

    func testPrivateBrowsingArchivesNoTabStateEvenWhenGivenAnArchive() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Private", url: nil, placement: .current)
        let other = BrowserTab(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab, other], selectedTabID: tab.id)
        let pool = BrowserPagePool(
            browsingMode: .privateBrowsing,
            tabStateArchive: archive
        )

        pool.select(tab: tab, space: space)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.select(tab: other, space: space)
        pool.archiveResidentTabStates()
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(profileID: space.profile.id, tabID: tab.id),
            "Private browsing must leave nothing on disk to restore."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: archive.rootDirectory.path),
            "A private pool must not even create the archive's directory."
        )
    }

    func testDeletingASpaceRemovesItsArchivedTabStates() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Deleted", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let survivingProfileID = UUID()
        let survivingTabID = TabID()
        archive.archive(
            interactionState: Data("other space".utf8),
            url: url,
            profileID: survivingProfileID,
            tabID: survivingTabID
        )
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            websiteDataStoreRemover: RecordingWebsiteDataStoreRemover(),
            tabStateArchive: archive
        )

        pool.select(tab: tab, space: space)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.unloadPage(for: tab.id)
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profile.id, tabID: tab.id)
        )

        try await pool.deleteData(for: space)
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(profileID: space.profile.id, tabID: tab.id),
            "Deleting a Space must take its archived session state with it."
        )
        XCTAssertNotNil(
            archive.archivedState(
                profileID: survivingProfileID,
                tabID: survivingTabID
            ),
            "Space deletion must not reach another Space's state."
        )
    }

    func testRelockingAProtectedSpacePurgesTheStateItsUnloadsLeftBehind() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secret = BrowserTab(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeSpace(
            tabs: [secret],
            selectedTabID: secret.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = BrowserTab(title: "Open", url: nil, placement: .current)
        let openSpace = makeSpace(tabs: [openTab], selectedTabID: openTab.id)
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pool.select(tab: openTab, space: openSpace)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.unloadPage(for: openTab.id)
        pool.select(tab: secret, space: protectedSpace)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        // The unload that leaves the residue: the page is gone from memory
        // long before the Space relocks, and its state is already on disk.
        pool.unloadPage(for: secret.id)
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(
                profileID: protectedSpace.profile.id,
                tabID: secret.id
            )
        )

        pool.relockProtectedSpace(protectedSpace)
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(
                profileID: protectedSpace.profile.id,
                tabID: secret.id
            ),
            "A relocked Space must leave no page state at rest."
        )
        XCTAssertNotNil(
            archive.archivedState(
                profileID: openSpace.profile.id,
                tabID: openTab.id
            ),
            "Relocking one Space must not reach another Space's state."
        )
    }

    func testRelockingAProtectedSpaceReleasesOnlyItsOwnResidentPages() throws {
        let secret = BrowserTab(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeSpace(
            tabs: [secret],
            selectedTabID: secret.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = BrowserTab(title: "Open", url: nil, placement: .current)
        let openSpace = makeSpace(tabs: [openTab], selectedTabID: openTab.id)
        let pool = BrowserPagePool()

        pool.select(tab: openTab, space: openSpace)
        pool.select(tab: secret, space: protectedSpace)
        XCTAssertTrue(pool.containsResidentPage(for: secret.id))

        pool.relockProtectedSpace(protectedSpace)

        XCTAssertFalse(pool.containsResidentPage(for: secret.id))
        XCTAssertTrue(pool.containsResidentPage(for: openTab.id))
    }

    func testAPurgedTabComesBackWithAPlainLoadAfterTheSpaceUnlocks() async throws {
        let archive = try makeTabStateArchive()
        let firstURL = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        var secret = BrowserTab(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeSpace(
            tabs: [secret],
            selectedTabID: secret.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pool.select(tab: secret, space: protectedSpace)
        let originalPage = try XCTUnwrap(pool.activePage)
        try await load(firstURL, in: originalPage)
        try await load(secondURL, in: originalPage)
        XCTAssertTrue(originalPage.webView.canGoBack)
        secret.url = secondURL
        pool.unloadPage(for: secret.id)
        pool.relockProtectedSpace(protectedSpace)
        await archive.flushPendingWrites()

        // What the next unlock does: the tab is selected again with no state to
        // restore into.
        pool.select(tab: secret, space: protectedSpace)
        let restoredPage = try XCTUnwrap(pool.activePage)

        XCTAssertFalse(restoredPage === originalPage)
        XCTAssertEqual(
            restoredPage.pendingNavigationURL ?? restoredPage.webView.url,
            secondURL,
            "A purged tab falls back to a plain load of its own URL."
        )
        XCTAssertTrue(
            restoredPage.webView.backForwardList.backList.isEmpty,
            "The back/forward list the purge took away must not come back."
        )

        pool.reconcile(validTabIDs: [])
    }

    func testRelockingAnOpenSpaceKeepsItsArchivedTabState() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = BrowserTab(title: "Ordinary", url: nil, placement: .current)
        let openSpace = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pool.select(tab: tab, space: openSpace)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.unloadPage(for: tab.id)
        await archive.flushPendingWrites()

        // The lock sweep hands over every Space it walks; an unprotected one has
        // nothing to relock, so its state has to survive the call.
        pool.relockProtectedSpace(openSpace)
        await archive.flushPendingWrites()

        XCTAssertNotNil(
            archive.archivedState(profileID: openSpace.profile.id, tabID: tab.id),
            "An open Space is never relocked, so nothing of its is purged."
        )
    }

    func testManualUnloadInAnUnlockedProtectedSpaceStillArchives() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let first = BrowserTab(title: "First", url: nil, placement: .current)
        let second = BrowserTab(title: "Second", url: nil, placement: .current)
        let protectedSpace = makeSpace(
            tabs: [first, second],
            selectedTabID: first.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pool.select(tab: first, space: protectedSpace)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        // Manual unloading, not a relock: an unlocked protected Space archives like
        // any other, which is what makes the relock purge worth having.
        pool.select(tab: second, space: protectedSpace)
        pool.unloadPage(for: first.id)
        await archive.flushPendingWrites()

        XCTAssertFalse(pool.containsResidentPage(for: first.id))
        XCTAssertNotNil(
            archive.archivedState(
                profileID: protectedSpace.profile.id,
                tabID: first.id
            )
        )

        pool.reconcile(validTabIDs: [])
    }

    func testASessionSweepKeepsArchivedTabsAndDropsDeletedOnes() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let live = BrowserTab(title: "Live", url: url, placement: .current)
        let closed = BrowserTab(title: "Closed", url: url, placement: .current)
        let deleted = BrowserTab(title: "Deleted", url: url, placement: .current)
        let space = makeSpace(tabs: [live, closed, deleted], selectedTabID: live.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        for tab in [live, closed, deleted] {
            archive.archive(
                interactionState: Data("state".utf8),
                url: url,
                profileID: space.profile.id,
                tabID: tab.id
            )
        }
        await archive.flushPendingWrites()
        let pool = BrowserPagePool(
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        session.closeTab(closed.id)
        XCTAssertTrue(session.deleteTab(deleted.id, in: space.id))
        pool.reconcile(session: session)
        await archive.flushPendingWrites()

        XCTAssertNotNil(
            archive.archivedState(profileID: space.profile.id, tabID: live.id)
        )
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profile.id, tabID: closed.id),
            "A closed tab can be reopened, so its state is worth keeping."
        )
        XCTAssertNil(
            archive.archivedState(profileID: space.profile.id, tabID: deleted.id),
            "A tab that is neither current nor archived has nothing to restore into."
        )
    }

    func testAnAdoptedPopupIsNeverArchived() async throws {
        let archive = try makeTabStateArchive()
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext(tabStateArchive: archive)

        _ = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )
        let popupTabID = try XCTUnwrap(context.pool.activeTabID)
        let popupPage = try XCTUnwrap(context.pool.activePage)
        context.pool.archiveResidentTabStates()
        context.pool.unloadPage(for: popupTabID)
        await archive.flushPendingWrites()

        XCTAssertTrue(popupPage.wasOpenedAsPopup)
        XCTAssertNil(
            archive.archivedState(
                profileID: popupPage.profileID,
                tabID: popupTabID
            ),
            "WebKit drives an adopted popup's window, so Crest never archives it."
        )
    }

    func testAPopupToAnotherApplicationsSchemeOpensNoTab() throws {
        let context = try makePopupContext()
        let tabCount = try XCTUnwrap(context.store.selectedSpace?.tabs.count)

        let webView = context.requestPopup(
            url: try XCTUnwrap(URL(string: "mailto:person@example.com")),
            navigationType: .linkActivated
        )

        XCTAssertNil(webView)
        XCTAssertEqual(
            context.store.selectedSpace?.tabs.count,
            tabCount,
            "window.open(\"mailto:…\") must not leave an empty tab behind."
        )
        XCTAssertTrue(context.pool.activePage === context.opener)
    }

    func testAPopupToABlockedSchemeOpensNoTab() throws {
        for address in ["javascript:alert(1)", "file:///etc/passwd"] {
            let context = try makePopupContext()
            let tabCount = try XCTUnwrap(context.store.selectedSpace?.tabs.count)

            let webView = context.requestPopup(
                url: try XCTUnwrap(URL(string: address)),
                navigationType: .linkActivated
            )

            XCTAssertNil(webView, "\(address) must not become a popup window.")
            XCTAssertEqual(context.store.selectedSpace?.tabs.count, tabCount)
        }
    }

    /// Loads `url` as a simulated response so a back/forward entry exists without
    /// a network fixture, and waits for WebKit to commit it.
    private func load(_ url: URL, in page: BrowserPage) async throws {
        page.webView.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        page.webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: """
                <!doctype html><html><body style="height: 4000px">\(url.path)</body></html>
                """
        )
        for attempt in 0..<200 {
            if page.webView.url == url, !page.webView.isLoading {
                return
            }
            if attempt < 199 {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        XCTFail("Timed out loading \(url).")
    }

    private func makeTabStateArchive() throws -> BrowserTabStateArchive {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("crest-pool-tab-state-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return BrowserTabStateArchive(rootDirectory: root)
    }

    private func makePopupContext(
        browsingMode: BrowserBrowsingMode = .standard,
        tabStateArchive: (any BrowserTabStateArchiving)? = nil
    ) throws -> PopupAdoptionContext {
        let openerTab = BrowserTab(title: "Opener", url: nil, placement: .current)
        let space = makeSpace(tabs: [openerTab], selectedTabID: openerTab.id)
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pool = BrowserPagePool(
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: tabStateArchive == nil,
            tabStateArchive: tabStateArchive,
            popupTabHost: store.popupTabHost
        )
        pool.select(session: store.session)
        return PopupAdoptionContext(
            store: store,
            pool: pool,
            opener: try XCTUnwrap(pool.activePage)
        )
    }

    /// A link followed in one card is followed for the window, so a visited-link
    /// restyle reaches every card rather than only the focused one.
    func testVisitedLinkStylingCoversEveryPresentedCard() throws {
        let groupID = SplitGroupID()
        let members = try (1...3).map { index in
            BrowserTab(
                title: "Member \(index)",
                url: try XCTUnwrap(URL(string: "https://split.crest.test/\(index)")),
                placement: .current,
                splitGroupID: groupID
            )
        }
        let background = BrowserTab(
            title: "Background",
            url: nil,
            placement: .current
        )
        let space = makeSpace(
            tabs: members + [background],
            selectedTabID: members[1].id
        )
        let pool = BrowserPagePool()

        pool.select(tab: background, space: space)
        pool.select(tab: members[1], space: space)

        XCTAssertEqual(
            pool.visitedLinkStylingTabIDs(in: space),
            members.map(\.id),
            "Every card on screen is restyled, in presented order."
        )

        let foreignSpace = makeSpace(
            tabs: members,
            selectedTabID: members[1].id
        )
        XCTAssertTrue(
            pool.visitedLinkStylingTabIDs(in: foreignSpace).isEmpty,
            "Another Space's history never reaches this Space's pages."
        )

        pool.reconcile(validTabIDs: [])
    }

    private func makeSpace(
        tabs: [BrowserTab],
        selectedTabID: TabID,
        accessPolicy: BrowserSpaceAccessPolicy = .open
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Test",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            accessPolicy: accessPolicy,
            selectedTabID: selectedTabID
        )
    }
}

@MainActor
private final class EmptyBrowserContentRuleListProvider:
    BrowserContentRuleListProviding
{
    func balancedRuleLists() async throws -> [WKContentRuleList] { [] }
}

final class BrowserPageLifecyclePolicyTests: XCTestCase {
    func testDesktopAndMobilePressureHaveDifferentReleaseBudgets() {
        XCTAssertEqual(
            BrowserMemoryPressureReleasePolicy.releaseLimit(
                for: .warning,
                eligiblePageCount: 8,
                platform: .desktop
            ),
            1
        )
        XCTAssertEqual(
            BrowserMemoryPressureReleasePolicy.releaseLimit(
                for: .critical,
                eligiblePageCount: 8,
                platform: .desktop
            ),
            4
        )
        XCTAssertEqual(
            BrowserMemoryPressureReleasePolicy.releaseLimit(
                for: .warning,
                eligiblePageCount: 8,
                platform: .mobile
            ),
            0
        )
        XCTAssertEqual(
            BrowserMemoryPressureReleasePolicy.releaseLimit(
                for: .critical,
                eligiblePageCount: 8,
                platform: .mobile
            ),
            1
        )
    }

    func testLevelsAreOrderedBySeverity() {
        XCTAssertLessThan(BrowserMemoryPressureLevel.warning, .critical)
    }

    func testTheCoalescerCollapsesOneSqueezeWithoutSwallowingAnEscalation() {
        var coalescer = BrowserMemoryPressureCoalescer()
        let squeeze = Date()

        XCTAssertTrue(coalescer.shouldHandle(.warning, at: squeeze))
        XCTAssertFalse(
            coalescer.shouldHandle(.warning, at: squeeze.addingTimeInterval(0.05)),
            "The second signal for one squeeze must not be handled again."
        )
        XCTAssertTrue(
            coalescer.shouldHandle(.critical, at: squeeze.addingTimeInterval(0.1)),
            "Critical pressure can release transients preserved by a warning."
        )
        XCTAssertFalse(
            coalescer.shouldHandle(.critical, at: squeeze.addingTimeInterval(0.15))
        )
        XCTAssertFalse(
            coalescer.shouldHandle(.warning, at: squeeze.addingTimeInterval(0.2)),
            "A warning trailing a critical squeeze has nothing left to ask for."
        )
        XCTAssertTrue(
            coalescer.shouldHandle(
                .warning,
                at: squeeze.addingTimeInterval(
                    BrowserMemoryPressureCoalescer.defaultWindow * 2
                )
            ),
            "Pressure that outlives the window is a new squeeze."
        )
    }

    func testAClockThatJumpedIsNeverAReasonToSkipPressureHandling() {
        var coalescer = BrowserMemoryPressureCoalescer()
        let squeeze = Date()

        XCTAssertTrue(coalescer.shouldHandle(.warning, at: squeeze))
        XCTAssertTrue(
            coalescer.shouldHandle(.warning, at: squeeze.addingTimeInterval(-60))
        )
    }
}

/// One opener page, its pool, and the store that owns their tabs, so popup tests
/// drive the real `WKUIDelegate` entry point instead of the pool's adoption API.
@MainActor
private struct PopupAdoptionContext {
    let store: BrowserStore
    let pool: BrowserPagePool
    let opener: BrowserPage

    /// Hands the opener a configuration copied from its own, which is what WebKit
    /// does before calling `createWebViewWith`.
    func requestPopup(url: URL?, navigationType: WKNavigationType) -> WKWebView? {
        guard
            let configuration = opener.webView.configuration
                .copy() as? WKWebViewConfiguration
        else { return nil }
        return opener.webView(
            opener.webView,
            createWebViewWith: configuration,
            for: StubPopupNavigationAction(url: url, navigationType: navigationType),
            windowFeatures: WKWindowFeatures()
        )
    }
}

/// WebKit never lets an app build a real `WKNavigationAction`, so popup tests
/// stand in for the one WebKit hands to `createWebViewWith`: no target frame and
/// a navigation type that selects the popup trigger under test.
private final class StubPopupNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest
    private let stubNavigationType: WKNavigationType

    init(url: URL?, navigationType: WKNavigationType) {
        // `window.open()` without a destination reaches WebKit as a request
        // without a URL, which a stub can only reproduce by clearing it.
        var request = URLRequest(url: URL(fileURLWithPath: "/"))
        request.url = url
        stubRequest = request
        stubNavigationType = navigationType
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { stubNavigationType }
    override var targetFrame: WKFrameInfo? { nil }
    var browserSourceOrigin: BrowserSiteOrigin? { nil }
}

@MainActor
private final class RecordingWebsiteDataStoreRemover:
    BrowserWebsiteDataStoreRemoving
{
    private(set) var removedProfileIDs: [UUID] = []

    func removePersistentDataStore(
        for profile: BrowsingProfile
    ) async throws {
        removedProfileIDs.append(profile.id)
    }
}

@MainActor
private final class SuspendingWebsiteDataStoreRemover:
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

private final class PagePoolAuthenticationChallengeSenderStub:
    NSObject,
    URLAuthenticationChallengeSender
{
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}
