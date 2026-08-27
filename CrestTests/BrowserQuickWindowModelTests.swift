import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserQuickWindowModelTests: XCTestCase {
    func testTargetBlankNavigationStaysInTheExactQuickWindowLease() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        let page = try XCTUnwrap(lease.page)
        let tabCount = try XCTUnwrap(
            context.browser.selectedSpace?.tabs.count
        )
        let destination = try XCTUnwrap(
            URL(string: "https://quick-target-blank.crest.test/destination")
        )

        let popupWebView = try page.requestTestPopup(
            url: destination,
            navigationType: .linkActivated
        )

        XCTAssertNil(popupWebView)
        XCTAssertTrue(context.model.pageLease === lease)
        XCTAssertTrue(context.model.page === page)
        XCTAssertEqual(page.pendingNavigationURL, destination)
        XCTAssertEqual(context.browser.selectedSpace?.tabs.count, tabCount)
        XCTAssertEqual(
            context.model.presentedRequest.id,
            context.requestBinding.request.id
        )
    }

    func testWindowOpenAboutBlankStaysInTheExactQuickWindowLease() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        let page = try XCTUnwrap(lease.page)
        let destination = try XCTUnwrap(
            URL(string: "about:blank#quick-window-open")
        )

        let popupWebView = try page.requestTestPopup(
            url: destination,
            navigationType: .other
        )

        XCTAssertNil(popupWebView)
        XCTAssertTrue(context.model.pageLease === lease)
        XCTAssertTrue(context.model.page === page)
        XCTAssertEqual(page.pendingNavigationURL, destination)
        XCTAssertEqual(
            context.browser.selectedSpace?.tabs.map(\.id),
            context.source.tabs.map(\.id)
        )
        XCTAssertEqual(
            context.model.presentedRequest.id,
            context.requestBinding.request.id
        )
    }

    func testSwitchingSpacesRejectsLateSourceLeaseMutations() throws {
        let context = try makeContext()
        let model = context.model

        model.preparePage(isActive: true)
        let sourceLease = try XCTUnwrap(model.pageLease)
        model.selectSpace(context.destination)

        XCTAssertNil(sourceLease.page)
        XCTAssertNil(model.pageLease)

        model.recordCompletedNavigation()
        XCTAssertFalse(model.archivePageIfNeeded())
        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.history
                .isEmpty == true
        )
        XCTAssertTrue(
            context.browser.session.space(id: context.destination.id)?.history
                .isEmpty == true
        )
        XCTAssertTrue(
            context.browser.session.space(id: context.destination.id)?
                .archivedTabs.isEmpty == true
        )
    }

    func testClosingArchivesOnlyTheCurrentLeaseInItsExactSpace() throws {
        let context = try makeContext()
        let model = context.model

        model.preparePage(isActive: true)

        XCTAssertTrue(model.archivePageIfNeeded())
        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?
                .archivedTabs.count,
            1
        )
        XCTAssertTrue(
            context.browser.session.space(id: context.destination.id)?
                .archivedTabs.isEmpty == true
        )
    }

    func testReplacementProfileInvalidatesTheLeaseWithoutRetargeting() throws {
        let context = try makeContext()
        let model = context.model
        model.preparePage(isActive: true)
        let lease = try XCTUnwrap(model.pageLease)
        let replacement = replacingProfile(of: context.source)
        context.browser.session = BrowserSession(
            spaces: [replacement, context.destination],
            selectedSpaceID: replacement.id
        )

        model.preparePage(isActive: true)

        XCTAssertNil(lease.page)
        XCTAssertNil(model.pageLease)
        XCTAssertNil(model.space)
        XCTAssertFalse(model.archivePageIfNeeded())
        XCTAssertFalse(model.promote(to: replacement))
        XCTAssertEqual(model.selectedAssignment.profileID, context.source.profile.id)
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

        context.model.preparePage(isActive: true)

        XCTAssertTrue(context.model.pageLease === lease)
        XCTAssertTrue(context.model.page === page)
        XCTAssertEqual(context.model.page?.profileID, renamedSource.profile.id)
    }

    func testPermanentlyInvalidatedLeaseIsRebuiltForTheSameAssignment() throws {
        let context = try makeContext()
        let model = context.model
        model.preparePage(isActive: true)
        let invalidatedLease = try XCTUnwrap(model.pageLease)

        context.pages.unloadPages(in: context.source.id)
        model.preparePage(isActive: true)

        let replacementLease = try XCTUnwrap(model.pageLease)
        XCTAssertFalse(replacementLease === invalidatedLease)
        XCTAssertNotNil(replacementLease.page)
        XCTAssertEqual(replacementLease.assignment, invalidatedLease.assignment)
    }

    func testMemoryPressureReleasedLeaseWaitsForExplicitRestore() throws {
        let context = try makeContext()
        let model = context.model
        model.preparePage(isActive: true)
        let releasedLease = try XCTUnwrap(model.pageLease)

        releasedLease.releaseForMemoryPressure()
        model.preparePage(isActive: true)

        XCTAssertTrue(model.pageLease === releasedLease)
        XCTAssertNil(releasedLease.page)
        XCTAssertTrue(releasedLease.wasReleasedForMemoryPressure)
    }

    func testRelockedQuickWindowDismissalArchivesItsValueSnapshot() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)

        context.model.releaseForUnavailableSpace()
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )

        context.model.releaseForDismissal()

        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?.archivedTabs.count,
            1
        )
        XCTAssertNil(context.model.releasedPageSnapshot)
    }

    func testDeletingSourceCannotArchiveItsRetainedValueSnapshot() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        context.model.releaseForUnavailableSpace()
        XCTAssertNotNil(context.model.releasedPageSnapshot)
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.source.id))
        defer { context.browser.family.finishDeletingSpace(context.source.id) }

        context.model.releaseForDismissal()

        XCTAssertTrue(
            context.browser.session.space(id: context.source.id)?.archivedTabs.isEmpty
                == true
        )
        XCTAssertNil(context.model.releasedPageSnapshot)
    }

    func testUnlockingRelockedQuickWindowRebuildsFromItsValueSnapshot() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let originalLease = try XCTUnwrap(context.model.pageLease)
        var lockedSource = context.source
        lockedSource.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(
            spaces: [lockedSource, context.destination],
            selectedSpaceID: lockedSource.id
        )
        context.model.releaseForUnavailableSpace()

        context.model.preparePage(isActive: true)
        context.model.restorePage()
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )

        let didUnlock = await context.spaceAccess.unlock(lockedSource)
        XCTAssertTrue(didUnlock)
        context.model.preparePage(isActive: true)

        let rebuiltLease = try XCTUnwrap(context.model.pageLease)
        XCTAssertFalse(rebuiltLease === originalLease)
        XCTAssertEqual(
            rebuiltLease.assignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
        XCTAssertNil(context.model.releasedPageSnapshot)
    }

    func testRelockedSourceRejectsLatePromotionAndRestore() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let lease = try XCTUnwrap(context.model.pageLease)
        var lockedSource = context.source
        lockedSource.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(
            spaces: [lockedSource, context.destination],
            selectedSpaceID: lockedSource.id
        )

        XCTAssertFalse(context.model.promote(to: context.destination))
        XCTAssertEqual(
            context.browser.session.space(id: context.destination.id)?.tabs.count,
            context.destination.tabs.count
        )

        let rejectedURL = try XCTUnwrap(
            URL(string: "https://locked-source.crest.test/rejected")
        )
        let presentedRequest = context.model.presentedRequest
        context.model.open(rejectedURL, isActive: true)
        XCTAssertEqual(context.model.presentedRequest, presentedRequest)
        XCTAssertTrue(context.model.pageLease === lease)

        lease.releaseForMemoryPressure()
        context.model.restorePage()
        XCTAssertNil(lease.page)
        XCTAssertNil(context.model.pageLease)
        context.model.preparePage(isActive: true)
        XCTAssertNil(context.model.pageLease)
        XCTAssertEqual(
            context.model.releasedPageSnapshot?.assignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
    }

    func testCompletedNavigationRecordsOneVisitOnlyInTheExactSourceSpace() async throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let page = try XCTUnwrap(context.model.page)
        let startingCount = page.completedNavigationCount
        let historyURL = try XCTUnwrap(
            URL(string: "https://quick-history.crest.test/completed")
        )

        page.webView.loadHTMLString(
            "<html><body>Quick Window</body></html>",
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

    func testFailedPromotionLeavesTheLeaseAndSelectionOpen() throws {
        let context = try makeContext()
        let model = context.model
        model.preparePage(isActive: true)
        let lease = try XCTUnwrap(model.pageLease)
        let staleDestination = replacingProfile(of: context.destination)

        XCTAssertFalse(model.promote(to: staleDestination))
        XCTAssertNotNil(lease.page)
        XCTAssertFalse(model.wasPromoted)
        XCTAssertEqual(
            context.browser.session.selectedSpaceID,
            context.source.id
        )
    }

    func testProtectedDestinationCannotBeSelectedOrPromotedWhileLocked() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        var protectedDestination = context.destination
        protectedDestination.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(
            spaces: [context.source, protectedDestination],
            selectedSpaceID: context.source.id
        )

        XCTAssertFalse(
            context.model.availableSpaces.contains {
                $0.id == protectedDestination.id
            }
        )
        context.model.selectSpace(protectedDestination)
        XCTAssertEqual(
            context.model.selectedAssignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
        XCTAssertFalse(context.model.promote(to: protectedDestination))
        XCTAssertEqual(
            context.browser.session.space(id: protectedDestination.id)?.tabs.count,
            protectedDestination.tabs.count
        )
        XCTAssertEqual(context.browser.session.selectedSpaceID, context.source.id)
    }

    func testCapturedDestinationCannotBeSelectedAfterItRelocks() throws {
        let context = try makeContext()
        let capturedDestination = context.destination
        var relockedDestination = context.destination
        relockedDestination.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(
            spaces: [context.source, relockedDestination],
            selectedSpaceID: context.source.id
        )

        context.model.selectSpace(capturedDestination)

        XCTAssertEqual(
            context.model.selectedAssignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
        XCTAssertEqual(context.browser.session.selectedSpaceID, context.source.id)
    }

    func testDeletingDestinationRejectsCapturedPromotionWithoutMutation() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        XCTAssertTrue(
            context.browser.family.beginDeletingSpace(context.destination.id)
        )
        defer { context.browser.family.finishDeletingSpace(context.destination.id) }

        XCTAssertFalse(context.model.promote(to: context.destination))
        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?.tabs.count,
            context.source.tabs.count
        )
        XCTAssertEqual(
            context.browser.session.space(id: context.destination.id)?.tabs.count,
            context.destination.tabs.count
        )
        XCTAssertEqual(context.browser.session.selectedSpaceID, context.source.id)
    }

    func testLivePromotionAdoptsOnlyTheExactAssignedPage() throws {
        let context = try makeContext(supportsLivePagePromotion: true)
        let model = context.model
        model.preparePage(isActive: true)
        let promotedPage = try XCTUnwrap(model.pageLease?.page)

        XCTAssertTrue(model.promote(to: context.source))
        XCTAssertTrue(model.wasPromoted)
        XCTAssertTrue(context.pages.activePage === promotedPage)
        XCTAssertEqual(context.pages.activePage?.profileID, context.source.profile.id)
    }

    func testEmptyPromotionSelectsTheExactDestinationWithoutOpeningATab() throws {
        let context = try makeContext(startsEmpty: true)
        let sourceTabCount = context.source.tabs.count
        let destinationTabCount = context.destination.tabs.count

        XCTAssertTrue(context.model.promote(to: context.destination))
        XCTAssertTrue(context.model.wasPromoted)
        XCTAssertEqual(
            context.browser.session.selectedSpaceID,
            context.destination.id
        )
        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?.tabs.count,
            sourceTabCount
        )
        XCTAssertEqual(
            context.browser.session.space(id: context.destination.id)?.tabs.count,
            destinationTabCount
        )
    }

    func testPresentationIdentityChangesWhenTheTargetWindowRuntimeIsReplaced() throws {
        let request = BrowserQuickWindowRequest.empty(
            spaceAssignment: BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(),
                profileID: UUID()
            )
        )
        let firstBrowser = BrowserStore.privateBrowsing()
        let firstPages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let secondBrowser = BrowserStore.privateBrowsing()
        let secondPages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )

        let first = BrowserQuickWindowPresentationIdentity(
            request: request,
            context: BrowserQuickWindowBrowsingContext(
                browser: firstBrowser,
                pages: firstPages,
                supportsLivePagePromotion: true
            )
        )
        let replacement = BrowserQuickWindowPresentationIdentity(
            request: request,
            context: BrowserQuickWindowBrowsingContext(
                browser: secondBrowser,
                pages: secondPages,
                supportsLivePagePromotion: true
            )
        )

        XCTAssertNotEqual(first, replacement)
    }

    func testStaleModelCannotOverwriteOrMutateAReplacementQuickWindow() throws {
        let context = try makeContext()
        context.model.preparePage(isActive: true)
        let oldPage = try XCTUnwrap(context.model.page)
        let replacement = BrowserQuickWindowRequest(
            id: UUID(),
            url: context.model.presentedRequest.url,
            spaceAssignment: context.model.presentedRequest.assignment,
            targetWindowID: BrowserWindowID(),
            sourcePresentation: BrowserPeekSourcePresentation(
                normalizedMinX: 0.1,
                normalizedMinY: 0.2,
                normalizedWidth: 0.3,
                normalizedHeight: 0.04,
                label: "Replacement"
            )
        )
        context.requestBinding.request = replacement
        let sourceTabs = context.source.tabs.count
        let destinationTabs = context.destination.tabs.count
        let rejectedURL = try XCTUnwrap(
            URL(string: "https://stale-quick-window.crest.test/rejected")
        )

        context.model.open(rejectedURL, isActive: true)
        context.model.selectSpace(context.destination)
        XCTAssertFalse(context.model.promote(to: context.destination))
        context.model.updatePresentedURL(rejectedURL)
        context.model.preparePage(isActive: true)
        context.model.restorePage()

        XCTAssertTrue(
            context.requestBinding.request.hasSamePresentationIdentity(
                as: replacement
            )
        )
        XCTAssertNotEqual(oldPage.url, rejectedURL)
        XCTAssertEqual(
            context.model.selectedAssignment,
            BrowserSpaceRuntimeAssignment(space: context.source)
        )
        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?.tabs.count,
            sourceTabs
        )
        XCTAssertEqual(
            context.browser.session.space(id: context.destination.id)?.tabs.count,
            destinationTabs
        )
        XCTAssertNil(context.model.pageLease)
        XCTAssertNotNil(context.model.releasedPageSnapshot)

        context.model.releaseForDismissal()
        context.model.releaseForDismissal()

        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?.archivedTabs.count,
            1
        )
        XCTAssertTrue(
            context.requestBinding.request.hasSamePresentationIdentity(
                as: replacement
            )
        )
    }

    private func makeContext(
        startsEmpty: Bool = false,
        supportsLivePagePromotion: Bool = false
    ) throws -> QuickWindowTestContext {
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
            usesEphemeralWebsiteDataStores: true,
            popupTabHost: browser.popupTabHost,
            openNewTab: { url in
                _ = browser.openNewTab(url: url)
            }
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: source)
        let request =
            startsEmpty
            ? BrowserQuickWindowRequest.empty(spaceAssignment: assignment)
            : BrowserQuickWindowRequest(
                url: try XCTUnwrap(URL(string: "about:blank")),
                spaceAssignment: assignment
            )
        let requestBinding = QuickWindowRequestBinding(request: request)
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
        let model = BrowserQuickWindowModel(
            request: request,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            supportsLivePagePromotion: supportsLivePagePromotion,
            preferences: .isolated,
            requestLifecycle: requestBinding.lifecycle
        )
        return QuickWindowTestContext(
            source: source,
            destination: destination,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            requestBinding: requestBinding,
            model: model
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

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for Quick Window state to change.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
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

    private struct QuickWindowTestContext {
        let source: BrowserSpace
        let destination: BrowserSpace
        let browser: BrowserStore
        let pages: BrowserPagePool
        let spaceAccess: BrowserSpaceAccessController
        let requestBinding: QuickWindowRequestBinding
        let model: BrowserQuickWindowModel
    }

    @MainActor
    private final class QuickWindowRequestBinding {
        var request: BrowserQuickWindowRequest

        init(request: BrowserQuickWindowRequest) {
            self.request = request
        }

        var lifecycle: BrowserQuickWindowRequestLifecycle {
            BrowserQuickWindowRequestLifecycle(
                isCurrent: { [weak self] expected in
                    self?.request.hasSamePresentationIdentity(as: expected)
                        == true
                },
                replace: { [weak self] expected, revised in
                    guard
                        self?.request.hasSamePresentationIdentity(as: expected)
                            == true
                    else { return false }
                    self?.request = revised
                    return true
                }
            )
        }
    }
}
