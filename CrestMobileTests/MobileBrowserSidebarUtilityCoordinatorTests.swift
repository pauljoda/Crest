import Foundation
import XCTest

@testable import CrestMobile

/// The compact shell's binding of the shared utility coordinator. The guards
/// themselves belong to `BrowserSidebarUtilityCoordinatorTests`; what is tested
/// here is only where this shell sends an action once a guard lets it through.
@MainActor
final class MobileBrowserSidebarUtilityCoordinatorTests: XCTestCase {
    /// The compact shell has one page, so history is routed through the shell
    /// rather than opened as a second tab in place.
    func testHistoryIsRoutedThroughTheShellInsteadOfOpeningATab() throws {
        let context = makeContext()
        var selectedTabs: [TabID] = []
        var openedURLs: [URL] = []
        let coordinator = makeCoordinator(
            context,
            selectTab: { selectedTabs.append($0) },
            openURL: { openedURLs.append($0) }
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)

        coordinator.actions.restoreArchivedTab(context.archived.id, assignment)
        coordinator.actions.openHistoryEntry(context.history, assignment)

        XCTAssertEqual(selectedTabs, [context.archived.id])
        XCTAssertEqual(openedURLs, [context.history.url])
        XCTAssertFalse(
            try XCTUnwrap(
                context.browser.session.space(id: context.source.id)
            ).tabs.contains(where: { $0.url == context.history.url })
        )
    }

    /// Finished files leave through the share sheet or the Files app, so those
    /// are the destinations the download surface offers.
    func testDownloadDestinationsAreTheCompactShellsExportRoutes() {
        let context = makeContext()
        let coordinator = makeCoordinator(
            context,
            selectTab: { _ in },
            openURL: { _ in }
        )

        XCTAssertEqual(coordinator.actions.downloadDestinations, [.share, .files])
    }

    /// Clearing a record goes through the store rather than straight to the
    /// download center, which is the only difference from the windowed shell.
    func testClearingADownloadGoesThroughThePageStore() {
        let context = makeContext()
        let coordinator = makeCoordinator(
            context,
            selectTab: { _ in },
            openURL: { _ in }
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)

        coordinator.actions.performDownloadAction(
            .clear(context.downloadItemID),
            assignment
        )

        XCTAssertTrue(context.pages.downloadCenter.items.isEmpty)
    }

    func testCompactDownloadsOpenAtomicallyClearsOnlyTheNewBadge() {
        let context = makeContext()
        let profileID = context.source.profile.id

        XCTAssertEqual(
            context.pages.downloadCenter.unacknowledgedItems(for: profileID).count,
            1
        )
        XCTAssertEqual(
            context.pages.downloadCenter.acknowledgeItems(for: profileID),
            1
        )
        XCTAssertTrue(
            context.pages.downloadCenter.unacknowledgedItems(for: profileID).isEmpty
        )
        XCTAssertEqual(
            context.pages.downloadCenter.items(for: profileID).map(\.id),
            [context.downloadItemID]
        )
        XCTAssertEqual(
            context.pages.downloadCenter.acknowledgeItems(for: profileID),
            0
        )
    }

    func testDownloadBadgeLifetimeIsPageStoreAndProfileScoped() {
        let context = makeContext()
        let sourceProfileID = context.source.profile.id
        let secondProfileID = UUID()
        var secondLedger = BrowserDownloadLedger()
        _ = secondLedger.begin(
            profileID: secondProfileID,
            filename: "other.bin"
        )
        let secondStore = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true,
            downloadLedger: secondLedger
        )

        _ = context.pages.downloadCenter.acknowledgeItems(
            for: sourceProfileID
        )

        XCTAssertTrue(
            context.pages.downloadCenter
                .unacknowledgedItems(for: sourceProfileID).isEmpty
        )
        XCTAssertEqual(
            secondStore.downloadCenter
                .unacknowledgedItems(for: secondProfileID).count,
            1
        )
        XCTAssertTrue(
            BrowserDownloadLedger()
                .unacknowledgedItems(for: sourceProfileID).isEmpty
        )
    }

    func testCompactDownloadsMenuPresentsVisibleAndSpokenUnreadCounts() {
        let empty = MobileDownloadsMenuAccess(
            newItemCount: 0,
            activeProgress: nil,
            open: {}
        )
        let single = MobileDownloadsMenuAccess(
            newItemCount: 1,
            activeProgress: 0.5,
            open: {}
        )
        let multiple = MobileDownloadsMenuAccess(
            newItemCount: 3,
            activeProgress: 0.75,
            open: {}
        )

        XCTAssertEqual(empty.rowTitle, "Downloads")
        XCTAssertEqual(empty.unreadAccessibilityValue, "0 new downloads")
        XCTAssertEqual(single.rowTitle, "Downloads (1)")
        XCTAssertEqual(single.unreadAccessibilityValue, "1 new download")
        XCTAssertEqual(multiple.rowTitle, "Downloads (3)")
        XCTAssertEqual(multiple.unreadAccessibilityValue, "3 new downloads")
    }

    private func makeCoordinator(
        _ context: Context,
        selectTab: @escaping (TabID) -> Void,
        openURL: @escaping (URL) -> Void
    ) -> BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: context.browser,
            pages: context.pages,
            spaceAccess: context.access,
            selectTab: selectTab,
            openURL: openURL
        )
    }

    private func makeContext() -> Context {
        let selectedTab = BrowserTab(
            id: TabID(rawValue: Self.uuid(1)),
            title: "Selected",
            url: URL(string: "about:blank"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let archivedTab = BrowserTab(
            id: TabID(rawValue: Self.uuid(2)),
            title: "Archived",
            url: URL(string: "about:blank#archived"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let archived = ArchivedTab(
            tab: archivedTab,
            archivedAt: Date(timeIntervalSince1970: 1_700_000_002),
            reason: .closed
        )
        let history = BrowserHistoryEntry(
            url: URL(fileURLWithPath: "/crest-mobile-sidebar-history"),
            title: "History",
            firstVisitedAt: Date(timeIntervalSince1970: 1_700_000_003),
            lastVisitedAt: Date(timeIntervalSince1970: 1_700_000_003)
        )
        let source = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(3)),
            profile: BrowsingProfile(id: Self.uuid(4)),
            name: "Source",
            symbol: "sidebar.left",
            accent: .indigo,
            folders: [],
            tabs: [selectedTab],
            archivedTabs: [archived],
            history: [history],
            selectedTabID: selectedTab.id
        )
        let destination = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(5)),
            profile: BrowsingProfile(id: Self.uuid(6)),
            name: "Destination",
            symbol: "square.grid.2x2",
            accent: .rose,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [source, destination],
                selectedSpaceID: source.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        var ledger = BrowserDownloadLedger()
        let downloadItemID = ledger.begin(
            profileID: source.profile.id,
            filename: "Crest.ipa",
            createdAt: Date(timeIntervalSince1970: 1_700_000_004)
        )
        return Context(
            browser: browser,
            pages: MobileBrowserPageStore(
                usesEphemeralWebsiteDataStores: true,
                downloadLedger: ledger
            ),
            downloadItemID: downloadItemID,
            access: BrowserSpaceAccessController(
                authenticator: AcceptingAuthenticator()
            ),
            source: source,
            archived: archived,
            history: history
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x4D, 0x4F, 0x42, 0x49, 0x4C, 0x45, 0x55, 0x54,
                0x49, 0x4C, 0x49, 0x54, 0x59, 0x00, 0x00, finalByte
            ))
    }

    private struct Context {
        let browser: BrowserStore
        let pages: MobileBrowserPageStore
        let downloadItemID: UUID
        let access: BrowserSpaceAccessController
        let source: BrowserSpace
        let archived: ArchivedTab
        let history: BrowserHistoryEntry
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
