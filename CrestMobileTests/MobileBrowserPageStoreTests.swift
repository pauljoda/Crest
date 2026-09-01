import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPageStoreTests: XCTestCase {

    func testStartPageCommandPaletteIssuesOneNavigationForAFreshPage() throws {
        let store = BrowserStore(
            session: makeSession(index: 0),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let url = try XCTUnwrap(URL(string: "https://example.com/search"))

        store.navigateSelectedTab(to: url)
        pages.selectAndLoad(url, in: store.session)

        XCTAssertEqual(
            try XCTUnwrap(pages.activePage).appInitiatedNavigationCount,
            1,
            "A Start Page submission must not ask a newly resident WebView to load twice."
        )
    }

    func testForegroundModifiedLinkCreatesSelectsAndLoadsOneCurrentSpacePage() throws {
        let store = BrowserStore(
            session: makeSession(index: 90),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = makeLinkRoutingPageStore(browser: store)
        let sourceSpaceID = try XCTUnwrap(store.selectedSpace?.id)
        pages.select(session: store.session)
        let sourcePage = try XCTUnwrap(pages.activePage)
        let url = try XCTUnwrap(URL(string: "https://slow.crest.test/foreground"))

        sourcePage.routeModifiedLink(url, selecting: true)

        XCTAssertEqual(store.selectedSpace?.id, sourceSpaceID)
        XCTAssertEqual(store.selectedTab?.url, url)
        XCTAssertEqual(pages.activePage?.tabID, store.selectedTab?.id)
        XCTAssertEqual(pages.activePage?.appInitiatedNavigationCount, 1)
    }

    func testBackgroundModifiedLinkWaitsForSelectionThenLoadsExactlyOnce() throws {
        let store = BrowserStore(
            session: makeSession(index: 91),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = makeLinkRoutingPageStore(browser: store)
        pages.select(session: store.session)
        let sourcePage = try XCTUnwrap(pages.activePage)
        let sourceTabID = try XCTUnwrap(store.selectedTab?.id)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:9/offline"))

        sourcePage.routeModifiedLink(url, selecting: false)

        let openedTab = try XCTUnwrap(
            store.selectedSpace?.tabs.first { $0.id != sourceTabID }
        )
        XCTAssertEqual(store.selectedTab?.id, sourceTabID)
        XCTAssertFalse(pages.containsResidentPage(for: openedTab.id))

        store.selectTab(openedTab.id)
        pages.select(session: store.session)

        XCTAssertEqual(pages.activePage?.tabID, openedTab.id)
        XCTAssertEqual(pages.activePage?.appInitiatedNavigationCount, 1)
    }

    // MARK: - Per-Space credential access

    func testCredentialAccessReconcilesAcrossAnExistingSpacePage() throws {
        var session = makeSession(index: 1)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        pages.select(session: session)
        XCTAssertTrue(try XCTUnwrap(pages.activePage).isCredentialAccessEnabled)

        let space = try XCTUnwrap(session.selectedSpace)
        var preferences = space.credentialPreferences
        preferences.isEnabled = false
        session.updateCredentialPreferences(preferences, in: space.id)
        pages.reconcileCredentialAccess(in: session)

        XCTAssertFalse(try XCTUnwrap(pages.activePage).isCredentialAccessEnabled)
        XCTAssertFalse(pages.downloadCenter.isCredentialAccessEnabled(in: space.id))
    }

    func testSelectingASpaceWithSavingOffBuildsItsPageWithCredentialAccessDisabled() throws {
        let session = makeSession(index: 2, savesCredentials: false)
        let space = try XCTUnwrap(session.selectedSpace)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)

        pages.select(session: session)

        XCTAssertFalse(try XCTUnwrap(pages.activePage).isCredentialAccessEnabled)
        XCTAssertFalse(
            pages.downloadCenter.isCredentialAccessEnabled(in: space.id),
            "Selecting a Space must carry its saving preference into HTTP authentication."
        )
    }

    func testDisablingCredentialAccessResetsAPendingFillRequest() throws {
        var session = makeSession(index: 3)
        let space = try XCTUnwrap(session.selectedSpace)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        pages.select(session: session)
        let page = try XCTUnwrap(pages.activePage)
        let loginOrigin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        page.credentialState.receive(
            try submitMessage(),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: nil
        )
        page.credentialState.receive(
            try documentStateMessage(),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: nil
        )
        XCTAssertNotNil(page.credentialSaveCandidate)

        var preferences = space.credentialPreferences
        preferences.isEnabled = false
        session.updateCredentialPreferences(preferences, in: space.id)
        pages.reconcileCredentialAccess(in: session)

        XCTAssertFalse(page.isCredentialAccessEnabled)
        XCTAssertNil(
            page.credentialSaveCandidate,
            "Turning saving off mid-session must take the pending save offer away with it."
        )
    }

    func testDisabledCredentialAccessRejectsAFillAndStopsFormCapture() async throws {
        let session = makeSession(index: 4, savesCredentials: false)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        pages.select(session: session)
        let page = try XCTUnwrap(pages.activePage)
        let request = URLRequest(
            url: try XCTUnwrap(URL(string: "https://forms.crest.test/login"))
        )
        page.webView.loadSimulatedRequest(
            request,
            responseHTML: """
                <!doctype html>
                <style>input { display: block; width: 220px; height: 32px; }</style>
                <form id="mobile-login">
                  <input autocomplete="username" value="mobile@example.com">
                  <input type="password" autocomplete="current-password" value="mobile-secret">
                  <button type="button">Sign In</button>
                </form>
                """
        )
        try await waitUntil { page.completedNavigationCount == 1 }

        let didCapture = try await page.webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.captureForTesting(selector) === true;",
            arguments: ["selector": "#mobile-login"],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        XCTAssertEqual(didCapture as? Bool, true)
        _ = try await page.webView.callAsyncJavaScript(
            "document.querySelector('#mobile-login').remove(); return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertNil(
            page.credentialSaveCandidate,
            "A Space with saving off must never offer to save what a form submitted."
        )
        XCTAssertNil(page.credentialFillRequest)
        await assertThrowsErrorAsync(
            try await page.fillGeneratedPassword("generated", for: UUID())
        )
    }

    func testTransientPeekPagesFollowTheirSpacesCredentialPreference() throws {
        var session = makeSession(index: 5)
        let space = try XCTUnwrap(session.selectedSpace)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let lease = try XCTUnwrap(
            pages.makeTransientPageLease(
                url: try XCTUnwrap(URL(string: "about:blank")),
                in: space
            )
        )
        XCTAssertTrue(try XCTUnwrap(lease.page).isCredentialAccessEnabled)

        var preferences = space.credentialPreferences
        preferences.isEnabled = false
        session.updateCredentialPreferences(preferences, in: space.id)
        pages.reconcileCredentialAccess(in: session)

        XCTAssertFalse(try XCTUnwrap(lease.page).isCredentialAccessEnabled)
    }

    func testDownloadOnlyTransientPageDismissesInsteadOfRemainingEmpty() async throws {
        let session = makeSession(index: 51)
        let space = try XCTUnwrap(session.selectedSpace)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        var dismissalCount = 0
        let lease = try XCTUnwrap(
            pages.makeTransientPageLease(
                url: try XCTUnwrap(URL(string: "about:blank")),
                in: space,
                onDownloadOnlyNavigation: { dismissalCount += 1 }
            )
        )
        let page = try XCTUnwrap(lease.page)

        page.discardDownloadOnlySurfaceIfNeeded()
        await Task.yield()

        XCTAssertEqual(dismissalCount, 1)
        XCTAssertNil(lease.page)
    }

    func testDownloadFromLoadedTransientPageKeepsItsExistingContent() async throws {
        let session = makeSession(index: 52)
        let space = try XCTUnwrap(session.selectedSpace)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        var dismissalCount = 0
        let lease = try XCTUnwrap(
            pages.makeTransientPageLease(
                url: try XCTUnwrap(URL(string: "about:blank")),
                in: space,
                onDownloadOnlyNavigation: { dismissalCount += 1 }
            )
        )
        let page = try XCTUnwrap(lease.page)
        page.webView(page.webView, didCommit: nil)

        page.discardDownloadOnlySurfaceIfNeeded()
        await Task.yield()

        XCTAssertEqual(dismissalCount, 0)
        XCTAssertNotNil(lease.page)
    }

    func testPrivateBrowsingKeepsCredentialAccessOffEvenWhenTheSpaceAllowsSaving() throws {
        let session = makeSession(index: 6)
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )

        pages.select(session: session)

        XCTAssertFalse(try XCTUnwrap(pages.activePage).isCredentialAccessEnabled)
    }

    // MARK: - Memory pressure

    func testCriticalPressureEventReleasesTheActiveTransientLeaseAWarningKeeps() throws {
        let session = makeSession(index: 7)
        let space = try XCTUnwrap(session.selectedSpace)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let url = try XCTUnwrap(URL(string: "about:blank"))
        pages.select(session: session)
        let activeLease = try XCTUnwrap(
            pages.makeTransientPageLease(url: url, in: space)
        )
        // `dispatch_source_get_data` is only defined for the duration of the
        // event handler, so the level has to be captured there and passed in as a
        // value. Reading it back off the source after a hop is what made every
        // squeeze — critical included — arrive here as a warning.

        pages.handleMemoryPressureEvent([.warning])

        XCTAssertNotNil(
            activeLease.page,
            "A warning deliberately preserves the transient surface in use."
        )

        pages.handleMemoryPressureEvent([.critical])

        XCTAssertNil(
            activeLease.page,
            "Critical pressure must reach critical handling instead of collapsing to a warning."
        )
        XCTAssertTrue(activeLease.wasReleasedForMemoryPressure)
        XCTAssertNotNil(pages.activePage)
    }

    // MARK: - Split View presentation

    func testSelectingAMemberPresentsTheWholeRunWithThatMemberFocused() throws {
        let split = makeSplitSession(memberCount: 3, selectedIndex: 1)
        let pages = makeSplitPageStore()

        pages.select(session: split.session)

        XCTAssertEqual(pages.presentedTabIDs, split.memberIDs)
        XCTAssertEqual(pages.activePage?.tabID, split.memberIDs[1])
        XCTAssertEqual(
            pages.residentPageCount,
            1,
            """
            Only the focused member is built by selection. The carousel asks for \
            its neighbours as their cells materialize, which is what keeps a \
            four-member group off four live web views on a phone.
            """
        )
    }

    func testATabOutsideARenderableRunPresentsAloneRatherThanAsASpecialCase() throws {
        let session = makeSession(index: 20)
        let pages = makeSplitPageStore()

        pages.select(session: session)

        XCTAssertEqual(
            pages.presentedTabIDs,
            [try XCTUnwrap(session.selectedTab?.id)]
        )
    }

    func testPreparingACardBuildsItsPageWithoutTakingFocus() throws {
        let split = makeSplitSession(memberCount: 3, selectedIndex: 0)
        let pages = makeSplitPageStore()
        pages.select(session: split.session)

        let prepared = pages.prepareResidentPage(
            for: split.memberIDs[1],
            in: split.session
        )

        XCTAssertEqual(prepared?.tabID, split.memberIDs[1])
        XCTAssertTrue(pages.containsResidentPage(for: split.memberIDs[1]))
        XCTAssertEqual(
            pages.activePage?.tabID,
            split.memberIDs[0],
            "Preparing a neighbour must never move focus off the selected card."
        )
    }

    func testPreparingACardRefusesTabsOutsideTheSelectedSpace() throws {
        let split = makeSplitSession(memberCount: 2, selectedIndex: 0)
        let otherSpace = makeSpace(index: 21, savesCredentials: true)
        let session = BrowserSession(
            spaces: [try XCTUnwrap(split.session.selectedSpace), otherSpace],
            selectedSpaceID: try XCTUnwrap(split.session.selectedSpaceID)
        )
        let pages = makeSplitPageStore()
        pages.select(session: session)

        XCTAssertNil(
            pages.prepareResidentPage(
                for: try XCTUnwrap(otherSpace.selectedTabID),
                in: session
            ),
            "A card only ever belongs to the selected Space."
        )
        XCTAssertNil(
            pages.prepareResidentPage(
                for: TabID(rawValue: fixedUUID(0xDEAD)),
                in: session
            )
        )
    }

    func testResidentPageAccessorRefusesNonMembersAndMismatchedAssignments() throws {
        let split = makeSplitSession(memberCount: 2, selectedIndex: 0)
        let space = try XCTUnwrap(split.session.selectedSpace)
        let pages = makeSplitPageStore()
        pages.select(session: split.session)
        pages.prepareResidentPage(for: split.memberIDs[1], in: split.session)

        XCTAssertNotNil(
            pages.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: split.memberIDs[1],
                    spaceID: space.id,
                    profileID: space.profile.id
                )
            )
        )
        XCTAssertNil(
            pages.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: split.memberIDs[1],
                    spaceID: space.id,
                    profileID: fixedUUID(0xBEEF)
                )
            ),
            """
            Binding a page across a profile boundary is exactly the isolation \
            failure per-Space browsing exists to prevent.
            """
        )
        XCTAssertNil(
            pages.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: split.nonMemberID,
                    spaceID: space.id,
                    profileID: space.profile.id
                )
            ),
            "A background tab with a resident page is not a card."
        )
    }

    func testDeactivatingPresentationTakesEveryCardAwayAtOnce() throws {
        let split = makeSplitSession(memberCount: 3, selectedIndex: 1)
        let pages = makeSplitPageStore()
        pages.select(session: split.session)
        pages.prepareResidentPage(for: split.memberIDs[0], in: split.session)

        pages.deactivatePagePresentation()

        XCTAssertTrue(
            pages.presentedTabIDs.isEmpty,
            "Half a split left on screen behind a lock gate is a privacy failure."
        )
        XCTAssertNil(pages.activePage)
        XCTAssertTrue(pages.containsResidentPage(for: split.memberIDs[0]))
        XCTAssertTrue(pages.containsResidentPage(for: split.memberIDs[1]))
    }

    // MARK: - Split View memory pressure

    func testCriticalPressureLeavesEveryCardAloneWhileAnOffScreenPageCanGo() async throws {
        let split = makeSplitSession(memberCount: 2, selectedIndex: 0)
        let pages = makeSplitPageStore()
        pages.select(session: split.session)
        pages.prepareResidentPage(
            for: split.memberIDs[1],
            in: split.session,
            at: fixedDate(1)
        )
        pages.prepareResidentPage(
            for: split.nonMemberID,
            in: split.session,
            at: fixedDate(2)
        )

        pages.handleMemoryPressure(.critical, at: fixedDate(10))
        await pages.waitForPendingMemoryPressureResponse()

        XCTAssertFalse(
            pages.containsResidentPage(for: split.nonMemberID),
            "The off-screen page is what critical pressure is for."
        )
        XCTAssertTrue(pages.containsResidentPage(for: split.memberIDs[0]))
        XCTAssertTrue(
            pages.containsResidentPage(for: split.memberIDs[1]),
            """
            An off-screen background page was available, so no presented card \
            should have been considered at all.
            """
        )
    }

    func testWarningPressureNeverReachesACardEvenWithNothingElseToGive() async throws {
        let split = makeSplitSession(memberCount: 4, selectedIndex: 0)
        let pages = makeSplitPageStore()
        pages.select(session: split.session)
        for (offset, memberID) in split.memberIDs.dropFirst().enumerated() {
            pages.prepareResidentPage(
                for: memberID,
                in: split.session,
                at: fixedDate(offset + 1)
            )
        }

        pages.handleMemoryPressure(.warning, at: fixedDate(10))
        await pages.waitForPendingMemoryPressureResponse()

        for memberID in split.memberIDs {
            XCTAssertTrue(
                pages.containsResidentPage(for: memberID),
                "A warning deliberately releases nothing on iOS."
            )
        }
    }

    func testCriticalFallbackEvictsTheOldestCardBeyondTheFocusedNeighbours() async throws {
        let split = makeSplitSession(memberCount: 4, selectedIndex: 0)
        let pages = makeSplitPageStore()
        pages.select(session: split.session)
        for (offset, memberID) in split.memberIDs.dropFirst().enumerated() {
            pages.prepareResidentPage(
                for: memberID,
                in: split.session,
                at: fixedDate(offset + 1)
            )
        }

        pages.handleMemoryPressure(.critical, at: fixedDate(10))
        await pages.waitForPendingMemoryPressureResponse()

        XCTAssertTrue(
            pages.containsResidentPage(for: split.memberIDs[0]),
            "The focused card is never a candidate."
        )
        XCTAssertTrue(
            pages.containsResidentPage(for: split.memberIDs[1]),
            "One swipe reaches the neighbour, so it stays resident."
        )
        XCTAssertFalse(
            pages.containsResidentPage(for: split.memberIDs[2]),
            """
            Least recently used first among the cards more than one swipe away: \
            member 2 was prepared before member 3.
            """
        )
        XCTAssertTrue(
            pages.containsResidentPage(for: split.memberIDs[3]),
            "Mobile releases one page per squeeze, not every eligible one."
        )
        XCTAssertEqual(
            pages.presentedTabIDs,
            split.memberIDs,
            """
            An evicted card is still a card: membership is what is on screen, so \
            the cell renders its unloaded placeholder and prepares again on \
            approach.
            """
        )
    }

    func testAnEvictedCardIsRebuiltWhenTheCarouselApproachesItAgain() async throws {
        let split = makeSplitSession(memberCount: 4, selectedIndex: 0)
        let pages = makeSplitPageStore()
        pages.select(session: split.session)
        for (offset, memberID) in split.memberIDs.dropFirst().enumerated() {
            pages.prepareResidentPage(
                for: memberID,
                in: split.session,
                at: fixedDate(offset + 1)
            )
        }
        pages.handleMemoryPressure(.critical, at: fixedDate(10))
        await pages.waitForPendingMemoryPressureResponse()
        XCTAssertFalse(pages.containsResidentPage(for: split.memberIDs[2]))

        pages.prepareResidentPage(
            for: split.memberIDs[2],
            in: split.session,
            at: fixedDate(20)
        )

        XCTAssertTrue(pages.containsResidentPage(for: split.memberIDs[2]))
        XCTAssertNotNil(
            pages.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: split.memberIDs[2],
                    spaceID: try XCTUnwrap(split.session.selectedSpace).id,
                    profileID: try XCTUnwrap(split.session.selectedSpace).profile.id
                )
            )
        )
    }

    func testAGroupCollapsingToOneCardMakesItsFormerMembersEvictableAgain() async throws {
        let split = makeSplitSession(memberCount: 2, selectedIndex: 0)
        let pages = makeSplitPageStore()
        pages.select(session: split.session)
        pages.prepareResidentPage(
            for: split.memberIDs[1],
            in: split.session,
            at: fixedDate(1)
        )

        // A remote "Separate All Tabs" arrives: the run is gone, so the former
        // member stops being a card and becomes an ordinary background tab.
        let collapsed = split.sessionWithoutSplitGroup
        pages.select(session: collapsed, at: fixedDate(5))

        XCTAssertEqual(pages.presentedTabIDs, [split.memberIDs[0]])

        pages.handleMemoryPressure(.critical, at: fixedDate(10))
        await pages.waitForPendingMemoryPressureResponse()

        XCTAssertFalse(
            pages.containsResidentPage(for: split.memberIDs[1]),
            "An ex-member is off screen, so the ordinary sweep may reclaim it."
        )
        XCTAssertTrue(pages.containsResidentPage(for: split.memberIDs[0]))
    }

    func testACardLeavingPresentationKeepsTheIdleAgeItAlreadyHad() async throws {
        let split = makeSplitSession(memberCount: 3, selectedIndex: 0)
        let pages = makeSplitPageStore()
        pages.select(session: split.session)
        // Prepared long ago, then joined by a background tab prepared just now.
        pages.prepareResidentPage(
            for: split.memberIDs[1],
            in: split.session,
            at: fixedDate(1)
        )
        pages.prepareResidentPage(
            for: split.nonMemberID,
            in: split.session,
            at: fixedDate(50)
        )

        pages.select(session: split.sessionWithoutSplitGroup, at: fixedDate(60))
        pages.handleMemoryPressure(.critical, at: fixedDate(70))
        await pages.waitForPendingMemoryPressureResponse()

        XCTAssertFalse(
            pages.containsResidentPage(for: split.memberIDs[1]),
            """
            Leaving presentation must not refresh the stamp: the card has been \
            out of attention since it was prepared, not since the group \
            dissolved, and refreshing would make the newer background page look \
            older than it is.
            """
        )
        XCTAssertTrue(pages.containsResidentPage(for: split.nonMemberID))
    }

    // MARK: - Presented release policy

    func testPresentedReleasePolicyAnswersNothingUntilCriticalWithNoAlternative() {
        let members = (0..<4).map { TabID(rawValue: fixedUUID(0x100 + $0)) }

        XCTAssertTrue(
            BrowserPresentedPageReleasePolicy.fallbackReleasableTabIDs(
                presentedTabIDs: members,
                focusedTabID: members[0],
                level: .warning,
                hasOtherReleasablePages: false
            ).isEmpty
        )
        XCTAssertTrue(
            BrowserPresentedPageReleasePolicy.fallbackReleasableTabIDs(
                presentedTabIDs: members,
                focusedTabID: members[0],
                level: .critical,
                hasOtherReleasablePages: true
            ).isEmpty
        )
    }

    func testPresentedReleasePolicyProtectsTheFocusedCardAndBothNeighbours() {
        let members = (0..<4).map { TabID(rawValue: fixedUUID(0x200 + $0)) }

        XCTAssertEqual(
            fallback(members, focusedIndex: 0),
            [members[2], members[3]]
        )
        XCTAssertEqual(fallback(members, focusedIndex: 1), [members[3]])
        XCTAssertEqual(fallback(members, focusedIndex: 2), [members[0]])
        XCTAssertEqual(
            fallback(members, focusedIndex: 3),
            [members[0], members[1]]
        )
    }

    func testPresentedReleasePolicyKeepsEveryCardOfASmallSplit() {
        let pair = (0..<2).map { TabID(rawValue: fixedUUID(0x300 + $0)) }
        let triple = (0..<3).map { TabID(rawValue: fixedUUID(0x310 + $0)) }

        XCTAssertTrue(fallback(pair, focusedIndex: 0).isEmpty)
        XCTAssertTrue(fallback(pair, focusedIndex: 1).isEmpty)
        XCTAssertTrue(
            fallback(triple, focusedIndex: 1).isEmpty,
            "Focused in the middle of three: every card is one swipe away."
        )
        XCTAssertEqual(fallback(triple, focusedIndex: 0), [triple[2]])
    }

    func testPresentedReleasePolicyAnswersNothingWithoutAFocusedMember() {
        let members = (0..<4).map { TabID(rawValue: fixedUUID(0x400 + $0)) }

        XCTAssertTrue(
            BrowserPresentedPageReleasePolicy.fallbackReleasableTabIDs(
                presentedTabIDs: members,
                focusedTabID: nil,
                level: .critical,
                hasOtherReleasablePages: false
            ).isEmpty,
            "Nothing is presented, so nothing is a card to reclaim."
        )
        XCTAssertTrue(
            BrowserPresentedPageReleasePolicy.fallbackReleasableTabIDs(
                presentedTabIDs: members,
                focusedTabID: TabID(rawValue: fixedUUID(0x4FF)),
                level: .critical,
                hasOtherReleasablePages: false
            ).isEmpty,
            "A focus outside the run means the caller is mid-reconciliation."
        )
    }

    // MARK: - Helpers

    private func fallback(
        _ members: [TabID],
        focusedIndex: Int
    ) -> [TabID] {
        BrowserPresentedPageReleasePolicy.fallbackReleasableTabIDs(
            presentedTabIDs: members,
            focusedTabID: members[focusedIndex],
            level: .critical,
            hasOtherReleasablePages: false
        )
    }

    /// A Space holding one split run plus one ordinary background tab after it.
    private func makeSplitSession(
        memberCount: Int,
        selectedIndex: Int
    ) -> SplitFixture {
        let groupID = SplitGroupID(rawValue: fixedUUID(0x5000))
        let members = (0..<memberCount).map { index in
            BrowserTab(
                id: TabID(rawValue: fixedUUID(0x5100 + index)),
                title: "Card \(index)",
                url: URL(string: "https://cards.crest.test/\(index)"),
                placement: .current,
                splitGroupID: groupID,
                lastActivatedAt: fixedDate(index)
            )
        }
        let background = BrowserTab(
            id: TabID(rawValue: fixedUUID(0x5200)),
            title: "Background",
            url: URL(string: "https://background.crest.test"),
            placement: .current,
            lastActivatedAt: fixedDate(0)
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(0x5300)),
            profile: BrowsingProfile(id: fixedUUID(0x5400)),
            name: "Split",
            symbol: "rectangle.split.2x1",
            accent: .indigo,
            folders: [],
            tabs: members + [background],
            selectedTabID: members[selectedIndex].id
        )
        return SplitFixture(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            memberIDs: members.map(\.id),
            nonMemberID: background.id
        )
    }

    private func makeSplitPageStore() -> MobileBrowserPageStore {
        MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true,
            // Deterministic: every off-focus page is unloadable, so these tests
            // measure the store's own eligibility rules rather than WebKit's
            // media state.
            residencyDecisionProvider: { _, _ in
                BrowserPageResidencyDecision(
                    isSelected: false,
                    keepsPageLoaded: false,
                    isPlayingMedia: false,
                    isCapturingMedia: false
                )
            }
        )
    }

    private func makeLinkRoutingPageStore(
        browser: BrowserStore
    ) -> MobileBrowserPageStore {
        MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true,
            openModifiedLink: { url, spaceID, selecting in
                guard
                    browser.openNewTab(
                        url: url,
                        in: spaceID,
                        selecting: selecting
                    ) != nil
                else { return nil }
                return browser.session
            }
        )
    }

    private func fixedDate(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset))
    }

    private func makeSession(
        index: Int,
        savesCredentials: Bool = true
    ) -> BrowserSession {
        let space = makeSpace(index: index, savesCredentials: savesCredentials)
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }

    private func makeSpace(
        index: Int,
        savesCredentials: Bool
    ) -> BrowserSpace {
        let tab = BrowserTab.startPage(
            id: TabID(rawValue: fixedUUID(index * 10 + 1)),
            placement: .current
        )
        var credentialPreferences = BrowserCredentialPreferences.default
        credentialPreferences.isEnabled = savesCredentials
        return BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(index * 10 + 2)),
            profile: BrowsingProfile(id: fixedUUID(index * 10 + 3)),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            credentialPreferences: credentialPreferences,
            selectedTabID: tab.id
        )
    }

    private func submitMessage() throws -> BrowserCredentialFormMessage {
        try message([
            "version": 1,
            "event": "submit",
            "trusted": true,
            "formID": "login-form",
            "username": "person@example.com",
            "password": "secret-value",
            "passwordKind": "current",
        ])
    }

    private func documentStateMessage() throws -> BrowserCredentialFormMessage {
        try message([
            "version": 1,
            "event": "documentState",
            "trusted": true,
            "hasVisiblePasswordField": false,
        ])
    }

    private func message(_ body: [String: Any]) throws -> BrowserCredentialFormMessage {
        try XCTUnwrap(BrowserCredentialFormMessage(body: body))
    }

    private func waitUntil(
        timeout: Duration = .seconds(8),
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

    private func assertThrowsErrorAsync(
        _ expression: @autoclosure () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected the call to throw.", file: file, line: line)
        } catch {}
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}

/// One split run, its members in order, and the background tab that follows it.
private struct SplitFixture {
    let session: BrowserSession
    let memberIDs: [TabID]
    let nonMemberID: TabID

    /// The same Space with the run dissolved, which is what a remote "Separate
    /// All Tabs" or a group broken up on another device materializes as.
    var sessionWithoutSplitGroup: BrowserSession {
        guard let space = session.selectedSpace else { return session }
        let flattened = BrowserSpace(
            id: space.id,
            profile: space.profile,
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            folders: space.folders,
            tabs: space.tabs.map { tab in
                var tab = tab
                tab.splitGroupID = nil
                return tab
            },
            selectedTabID: space.selectedTabID
        )
        return BrowserSession(
            spaces: [flattened],
            selectedSpaceID: flattened.id
        )
    }
}
