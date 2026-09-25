import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPeekModelTests: XCTestCase {
    func testSwitchingTabsRetainsThePeekDocumentAcrossHostRecreation() async throws {
        let context = try makeContext()
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let lease = try XCTUnwrap(context.model.pageLease)
        let page = try XCTUnwrap(context.model.page)
        try await waitUntil { page.completedNavigationCount > 0 }
        _ = try await page.webView.evaluateJavaScript(
            "document.body.innerHTML = '<input id=notes>'; document.querySelector('#notes').value = 'retained notes'")

        context.browser.selectSpace(context.destination.id)
        context.model.setActive(true)
        context.model.releaseForDisappearance()
        XCTAssertFalse(context.model.isSelected)
        XCTAssertFalse(lease.isActive)
        XCTAssertTrue(lease.page === page)
        XCTAssertTrue(context.coordinator.isPresentingPeek(context.request))

        context.browser.selectSpace(context.source.id)
        context.browser.selectTab(context.request.sourceTabID)
        let restored = BrowserPeekModel(
            request: context.request, browser: context.browser, pages: context.pages,
            spaceAccess: context.spaceAccess, coordinator: context.coordinator)
        XCTAssertTrue(restored.preparePage(isActive: true))
        XCTAssertTrue(restored.page === page)
        XCTAssertTrue(lease.isActive)
        let notes = try await page.webView.evaluateJavaScript("document.querySelector('#notes').value") as? String
        XCTAssertEqual(notes, "retained notes")

        restored.dismiss()
        context.pages.retainPeekPages(for: context.coordinator.peekRequests)
        XCTAssertNil(lease.page)
    }

    func testEachSourceTabOwnsItsPeekAndClosingOneReleasesOnlyItsPage() throws {
        let context = try makeContext()
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let firstLease = try XCTUnwrap(context.model.pageLease)
        let secondRequest = BrowserPeekRequest(
            url: context.request.url, sourceTabID: try XCTUnwrap(context.destination.tabs.first?.id),
            sourceTitle: "Second", spaceAssignment: BrowserSpaceRuntimeAssignment(space: context.destination),
            trigger: .modifierClick)
        context.coordinator.presentPeek(secondRequest)
        let second = BrowserPeekModel(
            request: secondRequest, browser: context.browser, pages: context.pages,
            spaceAccess: context.spaceAccess, coordinator: context.coordinator)
        XCTAssertTrue(second.preparePage(isActive: false))
        let secondPage = try XCTUnwrap(second.page)
        XCTAssertEqual(context.coordinator.peekRequests.count, 2)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertTrue(context.model.pageLease === firstLease)

        context.browser.deleteTab(context.request.sourceTabID, in: context.source.id)
        context.coordinator.reconcilePeeks(in: context.browser.session)
        context.pages.retainPeekPages(for: context.coordinator.peekRequests)
        XCTAssertEqual(context.coordinator.peekRequests, [secondRequest])
        XCTAssertNil(firstLease.page)
        XCTAssertTrue(second.page === secondPage)
        second.dismiss()
        context.pages.retainPeekPages(for: context.coordinator.peekRequests)
    }

    func testPullLoadsWhileHeldAndCommitKeepsTheSameLivePage() async throws {
        let context = try makeContext()
        var state = BrowserPeekMotionState(
            origin: CGPoint(x: 0.2, y: 0.2),
            location: CGPoint(x: 0.4, y: 0.4), scale: 0.4)
        context.coordinator.beginPeekDrag(context.request, state: state)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let lease = try XCTUnwrap(context.model.pageLease)
        let page = try XCTUnwrap(lease.page)
        try await waitUntil { page.completedNavigationCount > 0 }
        XCTAssertTrue(context.model.isPullStaged)

        state.releasedAt = Date()
        context.coordinator.updatePeekDrag(id: context.request.id, state: state)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertTrue(context.model.pageLease === lease)
        XCTAssertTrue(context.model.page === page)
        XCTAssertFalse(context.model.isPullStaged)
        context.model.releaseForDisappearance()
    }

    func testReturningPullReleasesItsLoadedPageWithoutCreatingATab() throws {
        let context = try makeContext()
        var state = BrowserPeekMotionState(
            origin: CGPoint(x: 0.2, y: 0.2),
            location: CGPoint(x: 0.4, y: 0.4), scale: 0.4)
        context.coordinator.beginPeekDrag(context.request, state: state)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let lease = try XCTUnwrap(context.model.pageLease)
        state.releasedAt = Date()
        state.returnsToSource = true
        context.coordinator.updatePeekDrag(id: context.request.id, state: state)
        XCTAssertNotNil(lease.page)
        context.model.finishReturningPull()
        XCTAssertNil(context.coordinator.peekRequest)
        XCTAssertNil(context.model.pageLease)
        XCTAssertNil(lease.page)
        XCTAssertEqual(context.pages.retainedTransientPageCount, 0)
        XCTAssertEqual(context.browser.selectedSpace?.tabs.map(\.id), context.source.tabs.map(\.id))
    }

    func testTargetBlankNavigationStaysInTheExactPeekLease() throws {
        let context = try makeContext()
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let lease = try XCTUnwrap(context.model.pageLease)
        let page = try XCTUnwrap(lease.page)
        let tabCount = try XCTUnwrap(
            context.browser.selectedSpace?.tabs.count
        )
        let destination = try XCTUnwrap(
            URL(string: "https://peek-target-blank.crest.test/destination")
        )

        let popupWebView = try page.requestTestPopup(
            url: destination,
            navigationType: .linkActivated
        )

        XCTAssertNil(popupWebView)
        XCTAssertTrue(context.model.pageLease === lease)
        XCTAssertTrue(context.model.page === page)
        XCTAssertEqual(page.navigationReporter?.pendingURL, destination)
        XCTAssertEqual(context.browser.selectedSpace?.tabs.count, tabCount)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testReplacementProfileInvalidatesTheExactPeekRuntime() throws {
        // A profile is replaced only in a persistent workspace, by the cloud.
        let context = try makeContext(browsingMode: .standard)
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        context.browser.replaceProfileForTesting(of: context.source.id)

        context.model.setSourceAvailable(context.model.space != nil)
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertNil(context.coordinator.peekRequest)
        XCTAssertFalse(context.model.promote(to: context.request.assignment))
    }

    func testStaleSourcePromotionCannotMutateEitherSpace() throws {
        let context = try makeContext(browsingMode: .standard)
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        context.browser.replaceProfileForTesting(of: context.source.id)
        let replacement = try XCTUnwrap(context.browser.session.space(id: context.source.id))

        XCTAssertFalse(context.model.promote(to: context.request.assignment))
        XCTAssertEqual(
            context.browser.session.space(id: replacement.id)?.tabs.count,
            replacement.tabs.count
        )
        XCTAssertEqual(
            context.browser.session.space(id: context.destination.id)?.tabs.count,
            context.destination.tabs.count
        )
        XCTAssertEqual(context.browser.selectedSpaceID, replacement.id)
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
        let context = try makeContext(browsingMode: .standard)
        context.model.preparePage(isActive: true)
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        context.browser.replaceProfileForTesting(of: context.destination.id)
        let replacement = try XCTUnwrap(context.browser.session.space(id: context.destination.id))

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
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.destination.id)
        let lockedDestination = try XCTUnwrap(context.browser.session.space(id: context.destination.id))

        XCTAssertFalse(context.model.promote(to: destinationAssignment))
        XCTAssertEqual(
            context.browser.session.space(id: lockedDestination.id)?.tabs.count,
            lockedDestination.tabs.count
        )
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
    }

    func testRelockedSourceRejectsLatePromotionPrepareAndRestore() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.source.id)
        let lockedSource = try XCTUnwrap(context.browser.session.space(id: context.source.id))

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
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.destination.id)

        context.model.selectLockedSpace(assignment)

        XCTAssertEqual(context.browser.selectedSpaceID, context.source.id)
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
        XCTAssertEqual(context.browser.selectedSpaceID, context.source.id)
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
                && context.browser.session.space(id: context.source.id)?.history.isEmpty == false
        }

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
            sourceTabID: try XCTUnwrap(context.destination.tabs.first?.id),
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
            sourceTabID: try XCTUnwrap(context.destination.tabs.first?.id),
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
        let source = context.source
        context.browser.updateSpaceIdentity(
            source.id, name: "Renamed Source", symbol: source.symbol, accent: source.accent)
        context.browser.addSpace()
        let inserted = try XCTUnwrap(context.browser.session.spaces.last)
        context.browser.family.send(
            ReorderSpaces(
                workspaceID: context.browser.family.workspaceID,
                spaceIDs: [context.destination.id.rawValue, inserted.id.rawValue, source.id.rawValue]),
            from: context.browser)
        context.browser.selectSpace(source.id)
        let renamedSource = try XCTUnwrap(context.browser.session.space(id: source.id))

        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertTrue(context.model.pageLease === lease)
        XCTAssertTrue(context.model.page === page)
        XCTAssertEqual(context.model.page?.profileID, renamedSource.profile.id)
    }

    private func makeContext(browsingMode: BrowserBrowsingMode = .privateBrowsing) throws -> PeekTestContext {
        let source = makeSpace(name: "Source")
        let destination = makeSpace(name: "Destination")
        let sourceTabID = try XCTUnwrap(source.tabs.first?.id)
        let browser = BrowserStore(
            session: BrowserSession(spaces: [source, destination]),
            showing: source.id, tabs: [source.id: sourceTabID],
            credentialVault: InMemoryCredentialVault(),
            browsingMode: browsingMode,
            core: .hostingPages()
        )
        let pages = BrowserPagePool(
            browser: browser,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: true,
            popupTabHost: browser.popupTabHost,
            openNewTab: { url in
                _ = browser.openNewTab(url: url)
            }
        )
        let request = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "about:blank")),
            sourceTabID: sourceTabID,
            sourceTitle: source.name,
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: source),
            trigger: .modifierClick
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentPeek(request)
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
        // The core refuses a locked Space's pages through the same grants.
        browser.attachSpaceAccess(spaceAccess)
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
            tabs: [tab]
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
