import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserTransientOverlayModelTests: XCTestCase {
    func testReplacementProfileInvalidatesTheExactTransientRuntime() throws {
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

    func testFailedPromotionLeavesTheExactTransientPageOpen() throws {
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

    func testSuccessfulPromotionRequestsSelectedTabPresentation() throws {
        var didPromote = false
        let context = try makeContext {
            didPromote = true
        }
        context.model.preparePage(isActive: true)

        XCTAssertTrue(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.destination)
            )
        )
        XCTAssertTrue(didPromote)
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

    func testRestoredPageRecordsTheSameExactHTTPSVisitAsANewPageGeneration() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        let originalPage = try XCTUnwrap(context.model.page)
        let historyURL = try XCTUnwrap(
            URL(string: "https://peek-history.crest.test/restored")
        )
        let originalStartingCount = originalPage.completedNavigationCount
        originalPage.webView.loadHTMLString(
            "<html><body>Original Peek</body></html>",
            baseURL: historyURL
        )
        try await waitUntil(timeout: .seconds(8)) {
            originalPage.completedNavigationCount > originalStartingCount
                && originalPage.url?.host() == historyURL.host()
        }
        context.model.recordCompletedNavigation(
            originalPage.completedNavigationCount,
            during: .committed
        )

        lease.releaseForMemoryPressure()
        context.model.restorePage()
        let restoredPage = try XCTUnwrap(context.model.page)
        let restoredStartingCount = restoredPage.completedNavigationCount
        restoredPage.webView.loadHTMLString(
            "<html><body>Restored Peek</body></html>",
            baseURL: historyURL
        )
        try await waitUntil(timeout: .seconds(8)) {
            restoredPage.completedNavigationCount > restoredStartingCount
                && restoredPage.url?.host() == historyURL.host()
        }
        context.model.recordCompletedNavigation(
            restoredPage.completedNavigationCount,
            during: .committed
        )

        let sourceHistory = try XCTUnwrap(
            context.browser.session.space(id: context.source.id)?.history
        )
        XCTAssertEqual(sourceHistory.count, 1)
        XCTAssertEqual(sourceHistory.first?.url.host(), historyURL.host())
        XCTAssertEqual(sourceHistory.first?.visitCount, 2)
        XCTAssertTrue(
            context.browser.session.space(id: context.destination.id)?.history.isEmpty
                == true
        )
    }

    func testRelockingTheSourceReleasesItsPageWithoutDismissingTheRequest() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)

        context.model.setSourceLocked(true)

        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.archivedTabs.isEmpty
                == true
        )
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

    func testRelockedSourceRejectsLatePromotion() throws {
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
        XCTAssertEqual(context.coordinator.peekRequest, context.request)

        lease.releaseForMemoryPressure()
        context.model.restorePage()
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertFalse(context.model.preparePage(isActive: true))
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(context.coordinator.peekRequest, context.request)
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

    func testDeletingSourceReleasesAndDismissesItsExactPeekWithoutSideEffects() throws {
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
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.archivedTabs.isEmpty
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

    func testQuickWindowRetargetChangesTheRenderedRuntimeIdentity() throws {
        var rememberedSpaceID: SpaceID?
        var rememberedURL: URL?
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
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let request = BrowserQuickWindowRequest(
            url: try XCTUnwrap(URL(string: "about:blank")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: source)
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentQuickWindow(request)
        let model = MobileBrowserTransientOverlayModel(
            request: .quickWindow(request),
            browser: browser,
            pages: pages,
            coordinator: coordinator,
            spaceAccess: BrowserSpaceAccessController(
                authenticator: BrowserPreviewAuthenticator(result: false)
            ),
            preferences: BrowserTransientBrowsingPreferences(
                archiveLifetime: nil,
                rememberSpace: { spaceID, url in
                    rememberedSpaceID = spaceID
                    rememberedURL = url
                }
            )
        )
        model.preparePage(isActive: true)
        let originalIdentity = MobileBrowserTransientRequest.quickWindow(request)
            .renderIdentity

        model.selectLockedSpace(
            BrowserSpaceRuntimeAssignment(space: destination)
        )

        let retargeted = try XCTUnwrap(coordinator.quickWindowRequest)
        XCTAssertEqual(retargeted.id, request.id)
        XCTAssertEqual(
            retargeted.assignment,
            BrowserSpaceRuntimeAssignment(space: destination)
        )
        XCTAssertNotEqual(
            MobileBrowserTransientRequest.quickWindow(retargeted).renderIdentity,
            originalIdentity
        )
        XCTAssertNil(model.pageLease)
        XCTAssertEqual(rememberedSpaceID, destination.id)
        XCTAssertEqual(rememberedURL, request.url)
        XCTAssertTrue(
            browser.session.space(id: source.id)?.archivedTabs.isEmpty == true
        )

        let sourceTabCount = browser.session.space(id: source.id)?.tabs.count
        let destinationTabCount = browser.session.space(id: destination.id)?.tabs.count
        model.dismiss()
        XCTAssertFalse(
            model.promote(
                to: BrowserSpaceRuntimeAssignment(space: destination)
            )
        )
        model.handleDisappearance()
        XCTAssertEqual(coordinator.quickWindowRequest, retargeted)
        XCTAssertEqual(
            browser.session.space(id: source.id)?.tabs.count,
            sourceTabCount
        )
        XCTAssertEqual(
            browser.session.space(id: destination.id)?.tabs.count,
            destinationTabCount
        )
        XCTAssertTrue(
            browser.session.space(id: source.id)?.archivedTabs.isEmpty == true
        )
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

    func testQuickWindowDismissArchivesExactlyOnceInItsSourceAssignment() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)

        context.model.dismiss()
        context.model.handleDisappearance()

        XCTAssertNil(context.coordinator.quickWindowRequest)
        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?.archivedTabs.count,
            1
        )
        XCTAssertTrue(
            context.browser.session.space(id: context.destination.id)?.archivedTabs.isEmpty
                == true
        )
    }

    func testReplacingAQuickWindowArchivesTheOutgoingExactLeaseOnce() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)
        let replacement = BrowserQuickWindowRequest(
            url: try XCTUnwrap(URL(string: "about:srcdoc")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                space: context.destination
            )
        )
        context.coordinator.presentQuickWindow(replacement)

        context.model.setActive(false)
        XCTAssertFalse(context.model.preparePage(isActive: false))
        context.model.restorePage()
        XCTAssertNotNil(context.model.releasedPageSnapshot)
        context.model.handleDisappearance()
        context.model.handleDisappearance()

        XCTAssertEqual(context.coordinator.quickWindowRequest, replacement)
        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?.archivedTabs.count,
            1
        )
        XCTAssertTrue(
            context.browser.session.space(id: context.destination.id)?.archivedTabs.isEmpty
                == true
        )
    }

    func testStagedCompletionReconcilesExactlyOnceWhenPeekCommits() throws {
        let context = try makeContext()
        context.coordinator.stagePeek(context.request)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let lease = try XCTUnwrap(context.model.pageLease)

        context.model.recordCompletedNavigation(1, during: .staged)
        XCTAssertNil(context.model.lastRecordedCompletedNavigationCount)
        context.coordinator.commitPeek(context.request)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertTrue(context.model.pageLease === lease)
        context.model.recordCompletedNavigation(1, during: .committed)
        context.model.recordCompletedNavigation(1, during: .committed)
        XCTAssertEqual(context.model.lastRecordedCompletedNavigationCount, 1)

        context.model.handleDisappearance()
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.history.isEmpty
                == true
        )
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.archivedTabs.isEmpty
                == true
        )
    }

    func testStagedWebLoadWritesOneExactHistoryEntryOnlyAfterCommit() async throws {
        let context = try makeContext()
        context.coordinator.stagePeek(context.request)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let page = try XCTUnwrap(context.model.page)
        let startingCount = page.completedNavigationCount
        let historyURL = try XCTUnwrap(
            URL(string: "https://peek-history.crest.test/committed")
        )

        page.webView.loadHTMLString(
            "<html><body>Committed Peek</body></html>",
            baseURL: historyURL
        )
        try await waitUntil(timeout: .seconds(8)) {
            page.completedNavigationCount > startingCount
                && page.url?.host() == historyURL.host()
        }
        let completedCount = page.completedNavigationCount
        context.model.recordCompletedNavigation(completedCount, during: .staged)
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.history.isEmpty
                == true
        )

        context.coordinator.commitPeek(context.request)
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.source.id))
        context.model.recordCompletedNavigation(completedCount, during: .committed)
        XCTAssertNil(context.model.lastRecordedCompletedNavigationCount)
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.history.isEmpty
                == true
        )
        context.browser.family.finishDeletingSpace(context.source.id)
        context.model.recordCompletedNavigation(completedCount, during: .committed)
        context.model.recordCompletedNavigation(completedCount, during: .committed)

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

    func testCancelledStagedPeekCreatesNoHistoryOrArchive() throws {
        let context = try makeContext()
        context.coordinator.stagePeek(context.request)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let lease = try XCTUnwrap(context.model.pageLease)

        context.model.recordCompletedNavigation(1, during: .staged)
        context.coordinator.cancelStagedPeek(id: context.request.id)
        context.model.handleDisappearance()

        XCTAssertNil(context.model.lastRecordedCompletedNavigationCount)
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.history.isEmpty
                == true
        )
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.archivedTabs.isEmpty
                == true
        )
    }

    func testQuickWindowPromotionNeverArchivesThePromotedPage() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)

        XCTAssertTrue(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.source)
            )
        )
        context.model.handleDisappearance()

        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.archivedTabs.isEmpty
                == true
        )
    }

    func testQuickWindowPromotionRemembersItsExactDestination() throws {
        var rememberedSpaceID: SpaceID?
        var rememberedURL: URL?
        let context = try makeQuickWindowContext(
            preferences: BrowserTransientBrowsingPreferences(
                archiveLifetime: nil,
                rememberSpace: { spaceID, url in
                    rememberedSpaceID = spaceID
                    rememberedURL = url
                }
            )
        )
        context.model.preparePage(isActive: true)

        XCTAssertTrue(
            context.model.promote(
                to: BrowserSpaceRuntimeAssignment(space: context.destination)
            )
        )
        XCTAssertEqual(rememberedSpaceID, context.destination.id)
        XCTAssertEqual(rememberedURL, context.request.url)
    }

    func testQuickWindowReplacementProfileCannotArchiveTheStaleLease() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)
        let replacement = replacingProfile(of: context.source)
        context.browser.session = BrowserSession(
            spaces: [replacement, context.destination],
            selectedSpaceID: replacement.id
        )

        XCTAssertFalse(context.model.preparePage(isActive: true))
        context.model.handleDisappearance()

        XCTAssertTrue(
            context.browser.session.space(id: replacement.id)?.archivedTabs.isEmpty
                == true
        )
        XCTAssertNil(context.coordinator.quickWindowRequest)
    }

    func testRelockedQuickWindowDismissalArchivesItsValueSnapshot() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)

        context.model.setSourceLocked(true)
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            context.request.assignment
        )

        context.model.dismiss()
        context.model.handleDisappearance()

        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?.archivedTabs.count,
            1
        )
        XCTAssertNil(context.coordinator.quickWindowRequest)
    }

    func testUnlockingRelockedQuickWindowRebuildsFromItsValueSnapshot() async throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)
        let originalLease = try XCTUnwrap(context.model.pageLease)
        var lockedSource = context.source
        lockedSource.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(
            spaces: [lockedSource, context.destination],
            selectedSpaceID: lockedSource.id
        )
        context.model.setSourceLocked(true)

        XCTAssertFalse(context.model.preparePage(isActive: true))
        context.model.restorePage()
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            context.request.assignment
        )

        let didUnlock = await context.spaceAccess.unlock(lockedSource)
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(context.model.preparePage(isActive: true))

        let rebuiltLease = try XCTUnwrap(context.model.pageLease)
        XCTAssertFalse(rebuiltLease === originalLease)
        XCTAssertEqual(rebuiltLease.assignment, context.request.assignment)
        XCTAssertEqual(rebuiltLease.recoverableURL, context.request.url)
        XCTAssertNil(context.model.releasedPageSnapshot)
    }

    func testSceneDeactivationBeforeLockObservationPreservesTheQuickWindowURL() async throws {
        let context = try makeQuickWindowContext()
        XCTAssertTrue(context.model.preparePage(isActive: true))
        let page = try XCTUnwrap(context.model.page)
        let currentURL = try XCTUnwrap(
            URL(string: "https://quick-window.crest.test/retained")
        )
        let startingCount = page.completedNavigationCount
        page.webView.loadHTMLString(
            "<html><body>Retained Quick Window</body></html>",
            baseURL: currentURL
        )
        try await waitUntil(timeout: .seconds(8)) {
            page.completedNavigationCount > startingCount
                && page.url?.host() == currentURL.host()
        }
        var lockedSource = context.source
        lockedSource.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(
            spaces: [lockedSource, context.destination],
            selectedSpaceID: lockedSource.id
        )

        context.model.setActive(false)

        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(context.model.releasedPageSnapshot?.url.host(), currentURL.host())
        let didUnlock = await context.spaceAccess.unlock(lockedSource)
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(context.model.preparePage(isActive: true))
        XCTAssertEqual(context.model.pageLease?.recoverableURL.host(), currentURL.host())
    }

    func testDeletingQuickWindowSourceDismissesWithoutArchiving() throws {
        let context = try makeQuickWindowContext()
        context.model.preparePage(isActive: true)
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.source.id))
        defer { context.browser.family.finishDeletingSpace(context.source.id) }

        context.model.setSourceAvailable(context.model.space != nil)
        context.model.handleDisappearance()

        XCTAssertNil(context.coordinator.quickWindowRequest)
        XCTAssertNil(context.model.pageLease)
        XCTAssertNil(context.model.releasedPageSnapshot)
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.archivedTabs.isEmpty
                == true
        )
    }

    func testZeroLifetimeQuickWindowArchivesAndDismissesDeterministically() async throws {
        let preferences = BrowserTransientBrowsingPreferences(
            archiveLifetime: 0,
            rememberSpace: { _, _ in }
        )
        let context = try makeQuickWindowContext(preferences: preferences)
        context.model.preparePage(isActive: true)

        await context.model.autoArchiveAfterInactivity()

        XCTAssertNil(context.coordinator.quickWindowRequest)
        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?.archivedTabs.count,
            1
        )
    }

    private func makeContext(
        didPromote: @escaping () -> Void = {}
    ) throws -> (
        source: BrowserSpace,
        destination: BrowserSpace,
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        coordinator: BrowserTransientBrowsingCoordinator,
        request: BrowserPeekRequest,
        spaceAccess: BrowserSpaceAccessController,
        model: MobileBrowserTransientOverlayModel
    ) {
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
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let request = BrowserPeekRequest(
            url: try XCTUnwrap(URL(string: "about:blank")),
            sourceTabID: try XCTUnwrap(source.selectedTabID),
            sourceTitle: source.name,
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: source),
            trigger: .longPress
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentPeek(request)
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
        return (
            source,
            destination,
            browser,
            pages,
            coordinator,
            request,
            spaceAccess,
            MobileBrowserTransientOverlayModel(
                request: .peek(request),
                browser: browser,
                pages: pages,
                coordinator: coordinator,
                spaceAccess: spaceAccess,
                preferences: .isolated,
                didPromote: didPromote
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
                XCTFail("Timed out waiting for transient browser state to change.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func makeQuickWindowContext(
        preferences: BrowserTransientBrowsingPreferences = .isolated
    ) throws -> (
        source: BrowserSpace,
        destination: BrowserSpace,
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        coordinator: BrowserTransientBrowsingCoordinator,
        request: BrowserQuickWindowRequest,
        spaceAccess: BrowserSpaceAccessController,
        model: MobileBrowserTransientOverlayModel
    ) {
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
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let request = BrowserQuickWindowRequest(
            url: try XCTUnwrap(URL(string: "about:blank")),
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: source)
        )
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentQuickWindow(request)
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
        return (
            source,
            destination,
            browser,
            pages,
            coordinator,
            request,
            spaceAccess,
            MobileBrowserTransientOverlayModel(
                request: .quickWindow(request),
                browser: browser,
                pages: pages,
                coordinator: coordinator,
                spaceAccess: spaceAccess,
                preferences: preferences
            )
        )
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
}
