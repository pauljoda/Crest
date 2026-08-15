import XCTest

@testable import CrestMobile

@MainActor
final class MobileContentBlockingActionTests: XCTestCase {
    func testStaleAssignmentDoesNotMutateEitherSpace() async throws {
        let fixture = makeFixture()
        let browser = fixture.browser
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        pages.select(session: browser.session)
        let pageActions = try XCTUnwrap(
            MobileSelectedPageActionPort(browser: browser, pages: pages)
        )
        let action = MobileContentBlockingAction(
            browser: browser,
            pages: pageActions
        )
        let firstPolicy = try XCTUnwrap(
            browser.session.space(id: fixture.firstSpaceID)
        ).browsingPreferences.contentBlockingPolicy
        let secondPolicy = try XCTUnwrap(
            browser.session.space(id: fixture.secondSpaceID)
        ).browsingPreferences.contentBlockingPolicy

        browser.selectSpace(fixture.secondSpaceID)

        let performed = await action.perform()

        XCTAssertFalse(performed)
        XCTAssertEqual(
            browser.session.space(id: fixture.firstSpaceID)?
                .browsingPreferences.contentBlockingPolicy,
            firstPolicy
        )
        XCTAssertEqual(
            browser.session.space(id: fixture.secondSpaceID)?
                .browsingPreferences.contentBlockingPolicy,
            secondPolicy
        )
    }

    func testValidatedActionReconcilesTheCommittedSnapshotAfterSelectionChanges() async throws {
        let fixture = makeFixture()
        let browser = fixture.browser
        let pageActions = RecordingMobilePageActions(
            pageAssignment: fixture.firstAssignment
        )
        pageActions.beforeRecordingReconciliation = {
            browser.selectSpace(fixture.secondSpaceID)
        }
        let action = MobileContentBlockingAction(
            browser: browser,
            pages: pageActions
        )

        let performed = await action.perform()

        XCTAssertTrue(performed)
        XCTAssertEqual(browser.session.selectedSpaceID, fixture.secondSpaceID)
        let reconciledSession = try XCTUnwrap(
            pageActions.reconciledSessions.first
        )
        XCTAssertEqual(reconciledSession.selectedSpaceID, fixture.firstSpaceID)
        XCTAssertEqual(
            reconciledSession.space(id: fixture.firstSpaceID)?
                .browsingPreferences.contentBlockingPolicy,
            .off
        )
        XCTAssertEqual(
            browser.session.space(id: fixture.firstSpaceID)?
                .browsingPreferences.contentBlockingPolicy,
            .off
        )
    }

    private func makeFixture() -> ContentBlockingFixture {
        let firstTab = BrowserTab(
            title: "First",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let secondTab = BrowserTab(
            title: "Second",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let firstSpace = BrowserSpace(
            id: SpaceID(rawValue: UUID()),
            profile: BrowsingProfile(),
            name: "First Space",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: [firstTab],
            selectedTabID: firstTab.id
        )
        let secondSpace = BrowserSpace(
            id: SpaceID(rawValue: UUID()),
            profile: BrowsingProfile(),
            name: "Second Space",
            symbol: "2.circle",
            accent: .teal,
            folders: [],
            tabs: [secondTab],
            selectedTabID: secondTab.id
        )
        return ContentBlockingFixture(
            browser: BrowserStore(
                session: BrowserSession(
                    spaces: [firstSpace, secondSpace],
                    selectedSpaceID: firstSpace.id
                ),
                persistence: InMemoryBrowserSessionPersistence()
            ),
            firstSpaceID: firstSpace.id,
            secondSpaceID: secondSpace.id,
            firstAssignment: BrowserTabRuntimeAssignment(
                tabID: firstTab.id,
                spaceID: firstSpace.id,
                profileID: firstSpace.profile.id
            )
        )
    }

    private struct ContentBlockingFixture {
        let browser: BrowserStore
        let firstSpaceID: SpaceID
        let secondSpaceID: SpaceID
        let firstAssignment: BrowserTabRuntimeAssignment
    }

    private final class RecordingMobilePageActions: MobilePageActions {
        var pageAssignment: BrowserTabRuntimeAssignment?
        var beforeRecordingReconciliation: () -> Void = {}
        private(set) var reconciledSessions: [BrowserSession] = []

        init(pageAssignment: BrowserTabRuntimeAssignment?) {
            self.pageAssignment = pageAssignment
        }

        var isAvailable: Bool { pageAssignment != nil }
        var activePage: MobileBrowserPage? { nil }
        var activeURL: URL? { nil }
        var canGoBack: Bool { false }
        var canGoForward: Bool { false }
        var backHistory: [BrowserNavigationHistoryItem] { [] }
        var forwardHistory: [BrowserNavigationHistoryItem] { [] }
        var preferredContentModeActionTitle: LocalizedStringResource {
            "Request Desktop Website"
        }
        var readerModeActionTitle: LocalizedStringResource { "Show Reader" }
        var readerModeState: BrowserReaderModeState { .unavailable }
        var pageZoomLabel: String { "100%" }

        func goBack() {}
        func goForward() {}
        func goBack(to item: BrowserNavigationHistoryItem) {}
        func goForward(to item: BrowserNavigationHistoryItem) {}
        func reloadOrStop() {}
        func reload() {}
        func stopLoading() {}
        func reloadFromOrigin() {}
        func clearSiteDataAndReload() async {}
        func togglePreferredContentMode() {}
        func toggleReaderMode() {}
        func presentFind() {}
        func zoomIn() {}
        func zoomOut() {}
        func resetZoom() {}
        func copyPageLink() -> Bool { false }
        func copyPageLinkAsMarkdown() -> Bool { false }
        func printPage() {}
        func exportPDF(to destination: MobileBrowserFileExportDestination) {}
        func exportWebArchive(to destination: MobileBrowserFileExportDestination) {}

        func reconcileContentBlocking(in session: BrowserSession) async {
            beforeRecordingReconciliation()
            reconciledSessions.append(session)
        }
    }
}
