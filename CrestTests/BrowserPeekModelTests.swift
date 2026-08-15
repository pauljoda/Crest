import XCTest

@testable import Crest

@MainActor
final class BrowserPeekModelTests: XCTestCase {
    func testReplacementProfileInvalidatesTheExactPeekRuntime() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        let replacement = replacingProfile(of: context.source)
        context.browser.session = BrowserSession(
            spaces: [replacement, context.destination],
            selectedSpaceID: replacement.id
        )

        context.model.setSourceAvailable(context.model.space != nil)
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertNil(context.coordinator.peekRequest)
        XCTAssertFalse(context.model.promote(to: context.request.assignment))
    }

    func testStaleSourcePromotionCannotMutateEitherSpace() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        let replacement = replacingProfile(of: context.source)
        context.browser.session = BrowserSession(
            spaces: [replacement, context.destination],
            selectedSpaceID: replacement.id
        )

        XCTAssertFalse(context.model.promote(to: context.request.assignment))
        XCTAssertEqual(
            context.browser.session.space(id: replacement.id)?.tabs.count,
            replacement.tabs.count
        )
        XCTAssertEqual(
            context.browser.session.space(id: context.destination.id)?.tabs.count,
            context.destination.tabs.count
        )
        XCTAssertEqual(context.browser.session.selectedSpaceID, replacement.id)
        XCTAssertNotNil(lease.page)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testFailedPromotionLeavesTheExactPeekOpen() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        context.browser.session = BrowserSession(
            spaces: [context.source],
            selectedSpaceID: context.source.id
        )

        XCTAssertFalse(context.model.promote(to: destinationAssignment))
        XCTAssertFalse(context.model.wasPromoted)
        XCTAssertNotNil(lease.page)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testSameSpacePromotionAdoptsTheExactTransientPage() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let promotedPage = try XCTUnwrap(context.model.pageLease?.page)

        XCTAssertTrue(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.source)
            )
        )
        XCTAssertTrue(context.model.wasPromoted)
        XCTAssertTrue(context.pages.activePage === promotedPage)
        XCTAssertEqual(context.pages.activePage?.profileID, context.source.profile.id)
        XCTAssertNil(context.coordinator.peekRequest)
    }

    func testCrossSpacePromotionRebuildsUnderTheDestinationProfile() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let sourcePage = try XCTUnwrap(context.model.pageLease?.page)

        XCTAssertTrue(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.destination)
            )
        )
        XCTAssertTrue(context.model.wasPromoted)
        XCTAssertNil(context.model.pageLease?.page)
        XCTAssertFalse(context.pages.activePage === sourcePage)
        XCTAssertEqual(
            context.pages.activePage?.profileID,
            context.destination.profile.id
        )
    }

    func testMemoryPressureReleaseRemainsExplicitlyRestorable() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)

        lease.releaseForMemoryPressure()
        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertTrue(context.model.pageLease === lease)
        XCTAssertNil(lease.page)

        context.model.restorePage()
        XCTAssertNotNil(lease.page)
    }

    func testRelockingTheSourceReleasesItsPageWithoutDismissingTheRequest() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)

        context.model.setSourceLocked(true)

        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testReplacementDestinationProfileRejectsTheCapturedMenuAssignment() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        let replacement = replacingProfile(of: context.destination)
        context.browser.session = BrowserSession(
            spaces: [context.source, replacement],
            selectedSpaceID: context.source.id
        )

        XCTAssertFalse(context.model.promote(to: destinationAssignment))
        XCTAssertEqual(
            context.browser.session.space(id: replacement.id)?.tabs.count,
            replacement.tabs.count
        )
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testLockedDestinationRejectsTheCapturedMenuAssignment() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        var lockedDestination = context.destination
        lockedDestination.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(
            spaces: [context.source, lockedDestination],
            selectedSpaceID: context.source.id
        )

        XCTAssertFalse(context.model.promote(to: destinationAssignment))
        XCTAssertEqual(
            context.browser.session.space(id: lockedDestination.id)?.tabs.count,
            lockedDestination.tabs.count
        )
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testLockedSourceStillOffersItsOnlyUnlockedAlternative() throws {
        let context = try makeContext()
        var lockedSource = context.source
        lockedSource.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(
            spaces: [lockedSource, context.destination],
            selectedSpaceID: lockedSource.id
        )

        XCTAssertEqual(
            Set(context.model.availableSpaces.map(\.id)),
            Set([lockedSource.id, context.destination.id])
        )
    }

    func testRelockedSourceRejectsLatePromotionPrepareAndRestore() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        var lockedSource = context.source
        lockedSource.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(
            spaces: [lockedSource, context.destination],
            selectedSpaceID: lockedSource.id
        )

        XCTAssertFalse(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.destination)
            )
        )
        XCTAssertEqual(
            context.browser.session.space(id: context.destination.id)?.tabs.count,
            context.destination.tabs.count
        )

        lease.releaseForMemoryPressure()
        context.model.restorePage()
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertFalse(context.model.preparePage(isActive: true))
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)

        let didUnlock = await context.spaceAccess.unlock(lockedSource)
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertEqual(
            context.model.pageLease?.assignment,
            BrowserSpaceRuntimeAssignment(space: lockedSource)
        )
    }

    func testRelockedCapturedSwitchDestinationCannotChangeSpaces() throws {
        let context = try makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.destination)
        var relockedDestination = context.destination
        relockedDestination.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(
            spaces: [context.source, relockedDestination],
            selectedSpaceID: context.source.id
        )

        context.model.selectLockedSpace(assignment)

        XCTAssertEqual(context.browser.session.selectedSpaceID, context.source.id)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testDeletingSourceReleasesAndDismissesItsExactPeekWithoutHistory() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.source.id))
        defer { context.browser.family.finishDeletingSpace(context.source.id) }

        context.model.setSourceAvailable(context.model.space != nil)

        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertNil(context.coordinator.peekRequest)
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.history.isEmpty
                == true
        )
    }

    func testDeletingDestinationRejectsCapturedPromotionWithoutMutation() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.destination)
        XCTAssertTrue(
            context.browser.family.beginDeletingSpace(context.destination.id)
        )
        defer { context.browser.family.finishDeletingSpace(context.destination.id) }

        XCTAssertFalse(context.model.promote(to: assignment))
        XCTAssertEqual(
            context.browser.session.space(id: context.destination.id)?.tabs.count,
            context.destination.tabs.count
        )
        XCTAssertEqual(context.browser.session.selectedSpaceID, context.source.id)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testCompletedNavigationRecordsOneVisitOnlyInTheExactSourceSpace() async throws {
        let context = try makeContext()
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let page = try XCTUnwrap(context.model.page)
        let startingCount = page.completedNavigationCount
        let historyURL = try XCTUnwrap(
            URL(string: "https://peek-history.crest.test/mac")
        )

        page.webView.loadHTMLString(
            "<html><body>Mac Peek</body></html>",
            baseURL: historyURL
        )
        try await waitUntil(timeout: .seconds(8)) {
            page.completedNavigationCount > startingCount
                && page.url?.host() == historyURL.host()
        }
        context.model.recordCompletedNavigation()

        let sourceHistory = try XCTUnwrap(
            context.browser.session.space(id: context.source.id)?.history
        )
        XCTAssertEqual(sourceHistory.count, 1)
        XCTAssertEqual(sourceHistory.first?.url.host(), historyURL.host())
        XCTAssertEqual(sourceHistory.first?.visitCount, 1)
        XCTAssertTrue(
            context.browser.session.space(id: context.destination.id)?.history.isEmpty
                == true
        )
    }

    func testStalePeekCannotDismissOrPromoteAReplacementRequest() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let replacement = BrowserPeekRequest(
            id: context.request.id,
            url: try XCTUnwrap(URL(string: "about:srcdoc")),
            sourceTabID: try XCTUnwrap(context.destination.selectedTabID),
            sourceTitle: context.destination.name,
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                space: context.destination
            ),
            trigger: .modifierClick
        )
        context.coordinator.presentPeek(replacement)
        let sourceTabCount = context.source.tabs.count
        let destinationTabCount = context.destination.tabs.count

        context.model.dismiss()
        XCTAssertFalse(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.destination)
            )
        )

        XCTAssertEqual(context.coordinator.peekRequest, replacement)
        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?.tabs.count,
            sourceTabCount
        )
        XCTAssertEqual(
            context.browser.session.space(id: context.destination.id)?.tabs.count,
            destinationTabCount
        )
    }

    func testStalePeekCannotRestoreItsReleasedPage() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        lease.releaseForMemoryPressure()
        let replacement = BrowserPeekRequest(
            id: context.request.id,
            url: try XCTUnwrap(URL(string: "about:srcdoc")),
            sourceTabID: try XCTUnwrap(context.destination.selectedTabID),
            sourceTitle: context.destination.name,
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                space: context.destination
            ),
            trigger: .modifierClick
        )
        context.coordinator.presentPeek(replacement)

        context.model.restorePage()

        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(context.coordinator.peekRequest, replacement)
    }

    func testSpaceInsertionReorderAndRenamePreserveTheExactRuntimeLease() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        let page = try XCTUnwrap(lease.page)
        var renamedSource = context.source
        renamedSource.name = "Renamed Source"
        let inserted = makeSpace(name: "Inserted")
        context.browser.session = BrowserSession(
            spaces: [context.destination, inserted, renamedSource],
            selectedSpaceID: renamedSource.id
        )

        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertTrue(context.model.pageLease === lease)
        XCTAssertTrue(context.model.page === page)
        XCTAssertEqual(context.model.page?.profileID, renamedSource.profile.id)
    }

    private func makeContext() throws -> PeekTestContext {
        let source = makeSpace(name: "Source")
        let destination = makeSpace(name: "Destination")
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [source, destination],
                selectedSpaceID: source.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            browsingMode: .privateBrowsing
        )
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let request = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "about:blank")),
            sourceTabID: try XCTUnwrap(source.selectedTabID),
            sourceTitle: source.name,
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: source),
            trigger: .modifierClick
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentPeek(request)
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPeekPreviewAuthenticator(authenticates: true)
        )
        return PeekTestContext(
            source: source,
            destination: destination,
            browser: browser,
            pages: pages,
            coordinator: coordinator,
            request: request,
            spaceAccess: spaceAccess,
            model: BrowserPeekModel(
                request: request,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                coordinator: coordinator
            )
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
                XCTFail("Timed out waiting for Peek state to change.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func makeSpace(name: String) -> BrowserSpace {
        let tab = BrowserTab.startPage()
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    private func replacingProfile(of source: BrowserSpace) -> BrowserSpace {
        BrowserSpace(
            id: source.id,
            profile: BrowsingProfile(),
            name: source.name,
            symbol: source.symbol,
            accent: source.accent,
            branding: source.branding,
            folders: source.folders,
            tabs: source.tabs,
            archivedTabs: source.archivedTabs,
            history: source.history,
            browsingPreferences: source.browsingPreferences,
            credentialPreferences: source.credentialPreferences,
            accessPolicy: source.accessPolicy,
            isSavedTabsExpanded: source.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: source.savedTabsExpansionModifiedAt,
            selectedTabID: source.selectedTabID
        )
    }

    private struct PeekTestContext {
        let source: BrowserSpace
        let destination: BrowserSpace
        let browser: BrowserStore
        let pages: BrowserPagePool
        let coordinator: BrowserTransientBrowsingCoordinator
        let request: BrowserPeekRequest
        let spaceAccess: BrowserSpaceAccessController
        let model: BrowserPeekModel
    }
}
