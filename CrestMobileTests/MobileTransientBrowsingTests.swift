import XCTest

@testable import CrestMobile

@MainActor
final class MobileTransientBrowsingTests: XCTestCase {
    func testMobileTransientPageUsesTheOwningSpaceAssignmentAndIsolatedWebsiteStore() throws {
        let session = BrowserSession.preview
        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.last)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let blankURL = try XCTUnwrap(URL(string: "about:blank"))

        let workLease = try XCTUnwrap(
            pages.makeTransientPageLease(
                url: blankURL,
                in: work
            )
        )
        let personalLease = try XCTUnwrap(
            pages.makeTransientPageLease(
                url: blankURL,
                in: personal
            )
        )
        let workPage = try XCTUnwrap(workLease.page)
        let personalPage = try XCTUnwrap(personalLease.page)
        defer {
            workLease.release()
            personalLease.release()
        }

        XCTAssertEqual(workPage.spaceID, work.id)
        XCTAssertEqual(workPage.profileID, work.profile.id)
        XCTAssertEqual(
            workLease.assignment,
            BrowserSpaceRuntimeAssignment(space: work)
        )
        XCTAssertEqual(
            personalLease.assignment,
            BrowserSpaceRuntimeAssignment(space: personal)
        )
        let workDataStore = workPage.webView.configuration.websiteDataStore
        let personalDataStore = personalPage.webView.configuration.websiteDataStore
        XCTAssertFalse(workDataStore.isPersistent)
        XCTAssertFalse(personalDataStore.isPersistent)
        XCTAssertEqual(
            workDataStore === personalDataStore,
            false,
            "Each profile keeps a separate nonpersistent store during isolated tests."
        )
    }

    func testMobileMemoryWarningReleasesTransientPagesBeforeTheActiveTab() throws {
        let session = BrowserSession.preview
        let work = try XCTUnwrap(session.spaces.first)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        let url = try XCTUnwrap(URL(string: "about:blank"))
        pages.select(session: session)
        let lease = try XCTUnwrap(
            pages.makeTransientPageLease(url: url, in: work)
        )

        XCTAssertNotNil(lease.page)
        XCTAssertEqual(pages.retainedTransientPageCount, 1)
        pages.handleMemoryPressure(.critical)

        XCTAssertNil(lease.page)
        XCTAssertTrue(lease.wasReleasedForMemoryPressure)
        XCTAssertNotNil(pages.activePage)
        XCTAssertEqual(pages.retainedTransientPageCount, 0)
    }

    func testMobileTransientLeaseDoesNotCrashWhenItsPageStoreHasBeenReleased() throws {
        let space = try XCTUnwrap(BrowserSession.preview.selectedSpace)
        let url = try XCTUnwrap(URL(string: "about:blank"))
        var pages: MobileBrowserPageStore? = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        let lease = try XCTUnwrap(
            try XCTUnwrap(pages).makeTransientPageLease(
                url: url,
                in: space
            )
        )

        lease.releaseForMemoryPressure()
        weak let releasedPages = pages
        pages = nil

        XCTAssertNil(releasedPages)
        lease.restore()
        XCTAssertNil(lease.page)
        XCTAssertTrue(lease.wasReleasedForMemoryPressure)
    }

    func testMobileCrossSpaceMoveRebuildsTheTabWithTheDestinationProfile() throws {
        var session = BrowserSession.preview
        let source = try XCTUnwrap(session.spaces.first)
        let destination = try XCTUnwrap(session.spaces.last)
        let tab = try XCTUnwrap(source.currentTabs.first)
        session.selectTab(tab.id)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)

        pages.select(session: session)
        let sourcePage = try XCTUnwrap(pages.activePage)
        XCTAssertEqual(sourcePage.spaceID, source.id)

        XCTAssertTrue(
            session.moveTab(tab.id, from: source.id, into: destination.id)
        )
        pages.reconcile(session: session)
        pages.select(session: session)

        let destinationPage = try XCTUnwrap(pages.activePage)
        XCTAssertFalse(sourcePage === destinationPage)
        XCTAssertEqual(destinationPage.spaceID, destination.id)
        XCTAssertEqual(destinationPage.profileID, destination.profile.id)
        XCTAssertFalse(
            sourcePage.webView.configuration.websiteDataStore
                === destinationPage.webView.configuration.websiteDataStore
        )
        XCTAssertFalse(destinationPage.webView.configuration.websiteDataStore.isPersistent)
    }

    func testPhoneAndTabletSharePeekPolicyAndQuickWindowRouting() throws {
        let tab = BrowserTab(
            title: "Saved",
            url: try XCTUnwrap(URL(string: "https://example.com/root")),
            placement: .saved
        )
        let spaceID = SpaceID()
        let profileID = UUID()
        let request = BrowserPeekPolicy.request(
            destinationURL: try XCTUnwrap(URL(string: "https://webkit.org")),
            context: BrowserPageNavigationContext(
                tab: tab,
                spaceID: spaceID,
                profileID: profileID
            ),
            isUserActivatedLink: true,
            isTopLevelNavigation: true,
            isAlternateModified: false
        )

        XCTAssertEqual(request?.spaceID, spaceID)
        XCTAssertEqual(request?.assignment.profileID, profileID)
        XCTAssertEqual(request?.trigger, .protectedSavedSite)
        XCTAssertEqual(BrowserLinkPreferences.default.externalLinkDestination, .quickWindow)
        XCTAssertEqual(BrowserLinkPreferences.default.quickWindowArchivePolicy, .after6Hours)
    }

    func testOrdinaryProtectedLinkPeekCarriesTheTrustedTapOriginWhenItMatches() throws {
        let tab = BrowserTab(
            title: "Pinned",
            url: try XCTUnwrap(URL(string: "https://example.com/root")),
            placement: .pinned
        )
        let destination = try XCTUnwrap(URL(string: "https://webkit.org/article"))
        let sourcePresentation = BrowserPeekSourcePresentation(
            normalizedMinX: 0.18,
            normalizedMinY: 0.42,
            normalizedWidth: 0.31,
            normalizedHeight: 0.06,
            normalizedTouchX: 0.23,
            normalizedTouchY: 0.45,
            label: "WebKit article"
        )

        let request = BrowserPeekPolicy.request(
            destinationURL: destination,
            context: BrowserPageNavigationContext(
                tab: tab,
                spaceID: SpaceID(),
                profileID: UUID()
            ),
            isUserActivatedLink: true,
            isTopLevelNavigation: true,
            isAlternateModified: false,
            sourcePresentation: sourcePresentation
        )

        XCTAssertEqual(request?.trigger, .protectedSavedSite)
        XCTAssertEqual(request?.sourcePresentation, sourcePresentation)
    }

    func testRecentLinkActivationOriginIsBoundedMatchingAndOneShot() throws {
        let destination = try XCTUnwrap(URL(string: "https://webkit.org/article"))
        let differentDestination = try XCTUnwrap(URL(string: "https://example.net/other"))
        let sourcePresentation = BrowserPeekSourcePresentation(
            normalizedMinX: 0.2,
            normalizedMinY: 0.3,
            normalizedWidth: 0.4,
            normalizedHeight: 0.08,
            label: "Article"
        )
        var store = MobileLinkActivationSourceStore(maximumAge: 1.25)

        store.record(
            destinationURL: destination,
            sourcePresentation: sourcePresentation,
            uptime: 10
        )
        XCTAssertNil(
            store.consume(destinationURL: differentDestination, uptime: 10.1),
            "An unrelated navigation must not inherit the preceding tap's position."
        )

        store.record(
            destinationURL: destination,
            sourcePresentation: sourcePresentation,
            uptime: 20
        )
        XCTAssertNil(
            store.consume(destinationURL: destination, uptime: 21.3),
            "A delayed script navigation must use the centered fallback."
        )

        store.record(
            destinationURL: destination,
            sourcePresentation: sourcePresentation,
            uptime: 30
        )
        XCTAssertEqual(
            store.consume(destinationURL: destination, uptime: 30.2),
            sourcePresentation
        )
        XCTAssertNil(
            store.consume(destinationURL: destination, uptime: 30.3),
            "One trusted activation point may animate only one Peek."
        )
    }

    func testMobileLinkLongPressBuildsASpaceIsolatedPeekRequest() throws {
        let tab = BrowserTab(
            title: "Long Press Source",
            url: try XCTUnwrap(URL(string: "https://example.com/source")),
            placement: .current
        )
        let spaceID = SpaceID()
        let destination = try XCTUnwrap(URL(string: "https://webkit.org/peek"))

        let sourcePresentation = BrowserPeekSourcePresentation(
            normalizedMinX: 0.12,
            normalizedMinY: 0.28,
            normalizedWidth: 0.34,
            normalizedHeight: 0.05,
            label: "Peek destination"
        )
        let request = BrowserPeekPolicy.longPressRequest(
            destinationURL: destination,
            context: BrowserPageNavigationContext(
                tab: tab,
                spaceID: spaceID,
                profileID: UUID()
            ),
            sourcePresentation: sourcePresentation
        )

        XCTAssertEqual(request?.url, destination)
        XCTAssertEqual(request?.sourceTabID, tab.id)
        XCTAssertEqual(request?.sourceTitle, tab.title)
        XCTAssertEqual(request?.spaceID, spaceID)
        XCTAssertEqual(request?.trigger, .longPress)
        XCTAssertEqual(request?.sourcePresentation, sourcePresentation)
        XCTAssertNil(
            BrowserPeekPolicy.longPressRequest(
                destinationURL: try XCTUnwrap(URL(string: "mailto:test@example.com")),
                context: BrowserPageNavigationContext(
                    tab: tab,
                    spaceID: spaceID,
                    profileID: UUID()
                )
            )
        )
    }

    func testEveryMobileTransientSurfaceResolvesAMissingOriginToBrowserCenter() throws {
        let spaceID = SpaceID()
        let url = try XCTUnwrap(URL(string: "https://example.com/transient"))
        let peek = BrowserPeekRequest(
            url: url,
            sourceTabID: TabID(),
            sourceTitle: "Source",
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: UUID()
            ),
            trigger: .modifierClick
        )
        let quickWindow = BrowserQuickWindowRequest(
            url: url,
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: UUID()
            )
        )

        for request in [
            MobileBrowserTransientRequest.peek(peek),
            MobileBrowserTransientRequest.quickWindow(quickWindow),
        ] {
            XCTAssertEqual(request.sourcePresentation.normalizedTouchX, 0.5)
            XCTAssertEqual(request.sourcePresentation.normalizedTouchY, 0.5)
            XCTAssertEqual(request.sourcePresentation.normalizedWidth, 0)
            XCTAssertEqual(request.sourcePresentation.normalizedHeight, 0)
            XCTAssertEqual(request.sourcePresentation.label, "Browser center")
        }
        XCTAssertEqual(
            MobileBrowserTransientRequest.peek(peek).spaceAssignment,
            peek.assignment
        )
        XCTAssertEqual(
            MobileBrowserTransientRequest.quickWindow(quickWindow).spaceAssignment,
            quickWindow.assignment
        )
    }

    func testMobileQuickWindowRetargetingPreservesItsWindowAndPresentationOrigin() throws {
        let source = BrowserPeekSourcePresentation(
            normalizedMinX: 0.12,
            normalizedMinY: 0.28,
            normalizedWidth: 0.34,
            normalizedHeight: 0.05,
            normalizedTouchX: 0.21,
            normalizedTouchY: 0.31,
            label: "External link"
        )
        let request = BrowserQuickWindowRequest(
            id: UUID(),
            url: try XCTUnwrap(URL(string: "https://example.com/source")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(),
                profileID: UUID()
            ),
            targetWindowID: BrowserWindowID(),
            sourcePresentation: source
        )
        let replacementAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )

        let retargeted = request.retargeted(
            to: try XCTUnwrap(URL(string: "https://example.com/destination")),
            assignment: replacementAssignment
        )

        XCTAssertEqual(retargeted.id, request.id)
        XCTAssertEqual(retargeted.targetWindowID, request.targetWindowID)
        XCTAssertEqual(retargeted.sourcePresentation, source)
        XCTAssertEqual(retargeted.assignment, replacementAssignment)
    }

    func testPeekChromeKeepsHistoryInternalInsteadOfRenderingNavigationButtons() {
        XCTAssertFalse(MobileBrowserTransientChromePolicy.rendersHistoryControls)
    }

    func testEveryTransientRoomIsLeftByTappingTheGroundAroundItsCard() {
        XCTAssertTrue(
            BrowserTransientCardArrangement.sheet.allowsScrimDismissal,
            "A handheld card's control bar sits where a downward drag belongs "
                + "to Reachability, so the ground around it is the way out."
        )
        XCTAssertTrue(
            BrowserTransientCardArrangement.canvas.allowsScrimDismissal
        )
        XCTAssertTrue(
            BrowserTransientCardArrangement.pointer.allowsScrimDismissal
        )
    }

    func testLinkPeekPressCommitsBeforeTheFingerIsReleased() async throws {
        let request = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://webkit.org/peek")),
            sourceTabID: TabID(),
            sourceTitle: "Held link",
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(),
                profileID: UUID()
            ),
            trigger: .longPress
        )
        let waits = LinkPeekPressWaits()
        let coordinator = MobileLinkPeekPressCoordinator(
            previewDelay: .milliseconds(10),
            minimumDuration: .milliseconds(30),
            wait: waits.wait
        )
        let opened = expectation(description: "Peek opens while the press remains active")
        var stagedRequest: BrowserPeekRequest?
        var openedRequest: BrowserPeekRequest?

        coordinator.begin(
            request: request,
            stage: { stagedRequest = $0 },
            commit: { request in
                openedRequest = request
                opened.fulfill()
            },
            cancelStaged: { _ in XCTFail("A committed press must not cancel") }
        )

        // The press asks for the lift wait before it stages anything, so the
        // order this test claims is read off the press's own steps rather than
        // off two timers a loaded machine can run down late: nothing is lifted
        // while the first wait is held, and ending it leaves the press asking
        // for the wait that would commit.
        await waits.waitUntilRequestCount(1)
        XCTAssertNil(stagedRequest)
        waits.elapse(0)
        await waits.waitUntilRequestCount(2)
        XCTAssertEqual(
            waits.requestedDurations,
            [.milliseconds(10), .milliseconds(20)]
        )
        XCTAssertEqual(stagedRequest, request)
        XCTAssertNil(openedRequest)
        XCTAssertFalse(coordinator.hasCommittedPress)

        // Committing is unreachable until the second wait ends, so the finger is
        // still down when Peek opens no matter how long the step itself takes.
        waits.elapse(1)
        await fulfillment(of: [opened], timeout: 10)
        XCTAssertEqual(openedRequest, request)
        XCTAssertTrue(coordinator.hasCommittedPress)

        coordinator.end()
    }

    func testLinkPeekPressReleaseAfterLiftButBeforeCommitSettlesTheLinkWithoutOpening() async throws {
        let request = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://webkit.org/cancelled-peek")),
            sourceTabID: TabID(),
            sourceTitle: "Short press",
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(),
                profileID: UUID()
            ),
            trigger: .longPress
        )
        let waits = LinkPeekPressWaits()
        let coordinator = MobileLinkPeekPressCoordinator(
            previewDelay: .milliseconds(10),
            minimumDuration: .milliseconds(80),
            wait: waits.wait
        )
        var stagedRequest: BrowserPeekRequest?
        var openedRequest: BrowserPeekRequest?
        var cancelledRequestID: UUID?

        coordinator.begin(
            request: request,
            stage: { stagedRequest = $0 },
            commit: { openedRequest = $0 },
            cancelStaged: { cancelledRequestID = $0 }
        )

        // Ending the lift wait runs the stage step, and the press then asks for
        // the wait that would commit it. That second request is what says the
        // link is lifted and not yet open, so the release below lands between the
        // two states without having to beat a timer to them.
        await waits.waitUntilRequestCount(1)
        waits.elapse(0)
        await waits.waitUntilRequestCount(2)
        XCTAssertEqual(stagedRequest, request)
        XCTAssertEqual(
            waits.requestedDurations,
            [.milliseconds(10), .milliseconds(70)]
        )

        coordinator.end()

        // Opening is unreachable while the commit wait is still held, so a
        // released link that settled here can never open afterwards.
        XCTAssertNil(openedRequest)
        XCTAssertEqual(cancelledRequestID, request.id)
        XCTAssertFalse(coordinator.hasCommittedPress)
        waits.cancelHeldWaits()
    }

    func testPrivateLongPressPeekKeepsItsEphemeralSpaceWhenPromoted() throws {
        let browser = BrowserStore.privateBrowsing()
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let privateSpace = try XCTUnwrap(browser.selectedSpace)
        let sourceTab = try XCTUnwrap(browser.selectedTab)
        let destination = try XCTUnwrap(URL(string: "https://webkit.org/private-peek"))
        let request = try XCTUnwrap(
            BrowserPeekPolicy.longPressRequest(
                destinationURL: destination,
                context: BrowserPageNavigationContext(
                    tab: sourceTab,
                    spaceID: privateSpace.id,
                    profileID: privateSpace.profile.id
                )
            )
        )

        let lease = try XCTUnwrap(
            pages.makeTransientPageLease(url: request.url, in: privateSpace)
        )
        let peekPage = try XCTUnwrap(lease.page)
        let privateStore = peekPage.webView.configuration.websiteDataStore
        XCTAssertEqual(request.spaceID, privateSpace.id)
        XCTAssertFalse(privateStore.isPersistent)
        XCTAssertNil(privateStore.identifier)

        let keptTabID = try XCTUnwrap(
            browser.openNewTab(url: request.url, in: request.spaceID)
        )
        let currentPrivateSpace = try XCTUnwrap(browser.selectedSpace)
        XCTAssertTrue(
            pages.adoptTransientPage(lease, as: keptTabID, in: currentPrivateSpace)
        )
        XCTAssertEqual(browser.session.spaces.map(\.id), [privateSpace.id])
        XCTAssertEqual(pages.activePage?.tabID, keptTabID)
        XCTAssertTrue(
            pages.activePage?.webView.configuration.websiteDataStore === privateStore
        )
    }

    func testDeletingSpaceReferencesRemovesRoutesChosenDestinationAndRememberedSites() throws {
        let suiteName = "MobileTransientBrowsingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowserLinkPreferenceStore(defaults: defaults, persistenceKey: "links")
        let deletedSpaceID = SpaceID()
        let survivingSpaceID = SpaceID()

        store.update { preferences in
            preferences.externalLinkSpaceID = deletedSpaceID
            preferences.routes = [
                BrowserLinkRoute(pattern: "work", destinationSpaceID: deletedSpaceID),
                BrowserLinkRoute(pattern: "personal", destinationSpaceID: survivingSpaceID),
            ]
            preferences.rememberedQuickWindowSpacesBySite = [
                "work.example": deletedSpaceID,
                "personal.example": survivingSpaceID,
            ]
        }

        store.removeReferences(to: deletedSpaceID)

        XCTAssertNil(store.preferences.externalLinkSpaceID)
        XCTAssertEqual(store.preferences.routes.map(\.destinationSpaceID), [survivingSpaceID])
        XCTAssertEqual(
            store.preferences.rememberedQuickWindowSpacesBySite,
            ["personal.example": survivingSpaceID]
        )
    }

    func testTransientCoordinatorNeverPresentsQuickWindowAndPeekTogether() throws {
        let coordinator = BrowserTransientBrowsingCoordinator()
        let quick = BrowserQuickWindowRequest(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(),
                profileID: UUID()
            )
        )
        let peek = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://webkit.org")),
            sourceTabID: TabID(),
            sourceTitle: "Source",
            spaceAssignment: quick.assignment,
            trigger: .modifierClick
        )

        coordinator.presentQuickWindow(quick)
        coordinator.presentPeek(peek)

        XCTAssertNil(coordinator.quickWindowRequest)
        XCTAssertEqual(coordinator.peekRequest, peek)
        XCTAssertEqual(coordinator.peekPresentationPhase, .committed)
    }

    func testTransientCoordinatorStagesCommitsAndCancelsOnlyTheMatchingPeek() throws {
        let coordinator = BrowserTransientBrowsingCoordinator()
        let first = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://webkit.org/first")),
            sourceTabID: TabID(),
            sourceTitle: "First",
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(),
                profileID: UUID()
            ),
            trigger: .longPress
        )
        let second = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "https://webkit.org/second")),
            sourceTabID: TabID(),
            sourceTitle: "Second",
            spaceAssignment: first.assignment,
            trigger: .longPress
        )

        coordinator.stagePeek(first)
        XCTAssertEqual(coordinator.peekRequest, first)
        XCTAssertEqual(coordinator.peekPresentationPhase, .staged)

        coordinator.cancelStagedPeek(id: second.id)
        XCTAssertEqual(coordinator.peekRequest, first)

        coordinator.commitPeek(first)
        XCTAssertEqual(coordinator.peekPresentationPhase, .committed)
        coordinator.cancelStagedPeek(id: first.id)
        XCTAssertEqual(coordinator.peekRequest, first)

        coordinator.stagePeek(second)
        coordinator.cancelStagedPeek(id: second.id)
        XCTAssertNil(coordinator.peekRequest)
        XCTAssertNil(coordinator.peekPresentationPhase)
    }
}

/// The two waits one press performs, ended when the test says so.
///
/// The release used to race the press's own commit timer: the test had 70ms
/// between the lift and the commit to call `end()`, and on a saturated machine it
/// arrived after the commit it was meant to precede — the settle never happened,
/// and the expectation waiting for it timed out. Holding the waits instead takes
/// the clock out of the test: every step is signalled by the press itself.
@MainActor
private final class LinkPeekPressWaits {
    private(set) var requestedDurations: [Duration] = []
    private var heldWaits: [CheckedContinuation<Void, any Error>?] = []
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func wait(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            requestedDurations.append(duration)
            heldWaits.append(continuation)
            announceRequest()
        }
    }

    /// Suspends until the press has asked for its `count`-th wait.
    func waitUntilRequestCount(_ count: Int) async {
        guard requestedDurations.count < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    /// Ends the wait at `index`, as if its duration had run out.
    func elapse(_ index: Int) {
        heldWaits[index]?.resume()
        heldWaits[index] = nil
    }

    /// Fails every wait still held the way a cancelled `Task.sleep` fails, so a
    /// press the test released leaves no continuation behind.
    func cancelHeldWaits() {
        for index in heldWaits.indices {
            heldWaits[index]?.resume(throwing: CancellationError())
            heldWaits[index] = nil
        }
    }

    private func announceRequest() {
        let requestedCount = requestedDurations.count
        let readyWaiters = requestWaiters.filter { $0.count <= requestedCount }
        requestWaiters.removeAll { $0.count <= requestedCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }
}
