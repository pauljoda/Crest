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
        session.selectSpace(destination.id)
        session.selectTab(tab.id)
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

    func testPrivatePeekKeepsItsEphemeralSpaceWhenPromoted() throws {
        let browser = BrowserStore.privateBrowsing()
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let privateSpace = try XCTUnwrap(browser.selectedSpace)
        let sourceTab = try XCTUnwrap(browser.selectedTab)
        let destination = try XCTUnwrap(URL(string: "https://webkit.org/private-peek"))
        let request = BrowserPeekRequest(
            url: destination,
            sourceTabID: sourceTab.id,
            sourceTitle: sourceTab.title,
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: privateSpace),
            trigger: .modifierClick
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

}
