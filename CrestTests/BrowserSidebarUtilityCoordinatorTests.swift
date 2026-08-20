import Foundation
import XCTest

@testable import Crest

/// The shared coordinator's behaviour, driven through a recording platform port
/// so the guards are tested apart from what either shell does afterwards. The
/// windowed shell's own binding is covered at the bottom; the compact shell's
/// is covered by `MobileBrowserSidebarUtilityCoordinatorTests`.
@MainActor
final class BrowserSidebarUtilityCoordinatorTests: XCTestCase {
    func testExactSelectedAssignmentRestoresArchiveAndOpensHistory() throws {
        let context = makeContext()
        let port = RecordedPlatformActions()
        let coordinator = makeCoordinator(context, port: port)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)

        coordinator.actions.restoreArchivedTab(context.archived.id, assignment)
        coordinator.actions.openHistoryEntry(context.history, assignment)

        let source = try XCTUnwrap(
            context.browser.session.space(id: context.source.id)
        )
        XCTAssertFalse(
            source.archivedTabs.contains(where: {
                $0.id == context.archived.id
            }))
        XCTAssertTrue(
            source.tabs.contains(where: {
                $0.id == context.archived.id
            }))
        XCTAssertEqual(port.restoredTabs, [context.archived.id])
        XCTAssertEqual(port.openedURLs, [context.history.url])
    }

    func testCapturedUtilityActionsRejectSelectionAndProfileChanges() throws {
        try assertActionsAreRejected { context in
            context.browser.selectSpace(context.destination.id)
        }
        try assertActionsAreRejected { context in
            self.replaceProfile(of: context.source, in: context.browser)
        }
    }

    func testCapturedUtilityActionsRejectLockedAndDeletingSpaces() throws {
        try assertActionsAreRejected(
            context: makeContext(isProtected: true),
            mutation: { _ in }
        )

        let deletingContext = makeContext()
        XCTAssertTrue(
            deletingContext.browser.family.beginDeletingSpace(
                deletingContext.source.id
            )
        )
        defer {
            deletingContext.browser.family.finishDeletingSpace(
                deletingContext.source.id
            )
        }
        try assertActionsAreRejected(context: deletingContext, mutation: { _ in })
    }

    /// Each download action reaches the shell's port with the item the policy
    /// approved, and a captured action whose Space has moved on reaches nothing.
    func testDownloadActionsReachThePlatformPortForOwnedItemsOnly() {
        let context = makeContext()
        let port = RecordedPlatformActions()
        let coordinator = makeCoordinator(context, port: port)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let itemID = context.downloadItemID

        coordinator.actions.performDownloadAction(
            .open(itemID, .revealInFinder),
            assignment
        )
        coordinator.actions.performDownloadAction(.cancel(itemID), assignment)
        coordinator.actions.performDownloadAction(.clear(itemID), assignment)

        XCTAssertEqual(port.openedDownloads.map { $0.item.id }, [itemID])
        XCTAssertEqual(port.openedDownloads.map { $0.destination }, [.revealInFinder])
        XCTAssertEqual(port.canceledDownloads, [itemID])
        XCTAssertEqual(port.clearedDownloads, [itemID])

        context.browser.selectSpace(context.destination.id)
        coordinator.actions.performDownloadAction(
            .open(itemID, .revealInFinder),
            assignment
        )
        coordinator.actions.performDownloadAction(.cancel(itemID), assignment)
        coordinator.actions.performDownloadAction(.clear(itemID), assignment)

        XCTAssertEqual(port.openedDownloads.count, 1)
        XCTAssertEqual(port.canceledDownloads, [itemID])
        XCTAssertEqual(port.clearedDownloads, [itemID])
    }

    func testDownloadPolicyRequiresExactSelectedUnlockedProfileOwnership() {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let exactItem = downloadItem(profileID: assignment.profileID, id: Self.uuid(20))
        let wrongProfileItem = downloadItem(
            profileID: Self.uuid(21),
            id: exactItem.id
        )
        let action = BrowserUtilityDownloadAction.clear(exactItem.id)

        XCTAssertEqual(
            BrowserSidebarUtilityActionPolicy.downloadItem(
                for: action,
                matching: assignment,
                in: context.browser,
                accessController: context.access,
                itemsForProfile: { _ in [exactItem] }
            ),
            exactItem
        )
        XCTAssertNil(
            BrowserSidebarUtilityActionPolicy.downloadItem(
                for: action,
                matching: assignment,
                in: context.browser,
                accessController: context.access,
                itemsForProfile: { _ in [wrongProfileItem] }
            )
        )

        context.browser.selectSpace(context.destination.id)
        XCTAssertNil(
            BrowserSidebarUtilityActionPolicy.downloadItem(
                for: action,
                matching: assignment,
                in: context.browser,
                accessController: context.access,
                itemsForProfile: { _ in [exactItem] }
            )
        )

        let lockedContext = makeContext(isProtected: true)
        let lockedAssignment = BrowserSpaceRuntimeAssignment(
            space: lockedContext.source
        )
        let lockedItem = downloadItem(
            profileID: lockedAssignment.profileID,
            id: Self.uuid(22)
        )
        XCTAssertNil(
            BrowserSidebarUtilityActionPolicy.downloadItem(
                for: .clear(lockedItem.id),
                matching: lockedAssignment,
                in: lockedContext.browser,
                accessController: lockedContext.access,
                itemsForProfile: { _ in [lockedItem] }
            )
        )

        let deletingContext = makeContext()
        let deletingAssignment = BrowserSpaceRuntimeAssignment(
            space: deletingContext.source
        )
        let deletingItem = downloadItem(
            profileID: deletingAssignment.profileID,
            id: Self.uuid(23)
        )
        XCTAssertTrue(
            deletingContext.browser.family.beginDeletingSpace(
                deletingContext.source.id
            )
        )
        defer {
            deletingContext.browser.family.finishDeletingSpace(
                deletingContext.source.id
            )
        }
        XCTAssertNil(
            BrowserSidebarUtilityActionPolicy.downloadItem(
                for: .clear(deletingItem.id),
                matching: deletingAssignment,
                in: deletingContext.browser,
                accessController: deletingContext.access,
                itemsForProfile: { _ in [deletingItem] }
            )
        )

        let replacementContext = makeContext()
        let replacementAssignment = BrowserSpaceRuntimeAssignment(
            space: replacementContext.source
        )
        let replacementItem = downloadItem(
            profileID: replacementAssignment.profileID,
            id: Self.uuid(24)
        )
        replaceProfile(
            of: replacementContext.source,
            in: replacementContext.browser
        )
        XCTAssertNil(
            BrowserSidebarUtilityActionPolicy.downloadItem(
                for: .clear(replacementItem.id),
                matching: replacementAssignment,
                in: replacementContext.browser,
                accessController: replacementContext.access,
                itemsForProfile: { _ in [replacementItem] }
            )
        )
    }

    /// The windowed shell answers history in place: a new tab in the Space the
    /// reader is looking at, and Finder destinations for finished files.
    func testPagePoolBindingOpensHistoryInPlace() throws {
        let context = makeContext()
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let coordinator = BrowserSidebarUtilityCoordinator(
            browser: context.browser,
            pages: pages,
            spaceAccess: context.access
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)

        coordinator.actions.openHistoryEntry(context.history, assignment)

        XCTAssertEqual(
            coordinator.actions.downloadDestinations,
            [.open, .revealInFinder]
        )
        XCTAssertTrue(
            try XCTUnwrap(
                context.browser.session.space(id: context.source.id)
            ).tabs.contains(where: { $0.url == context.history.url })
        )
    }

    private func assertActionsAreRejected(
        context: Context? = nil,
        mutation: (Context) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let context = context ?? makeContext()
        let port = RecordedPlatformActions()
        let coordinator = makeCoordinator(context, port: port)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        mutation(context)

        coordinator.actions.restoreArchivedTab(context.archived.id, assignment)
        coordinator.actions.openHistoryEntry(context.history, assignment)

        XCTAssertTrue(port.restoredTabs.isEmpty, file: file, line: line)
        XCTAssertTrue(port.openedURLs.isEmpty, file: file, line: line)
        let source = try XCTUnwrap(
            context.browser.session.space(id: context.source.id)
        )
        XCTAssertEqual(
            source.archivedTabs.map(\.id),
            [context.archived.id],
            file: file,
            line: line
        )
        XCTAssertFalse(
            source.tabs.contains(where: { $0.url == context.history.url }),
            file: file,
            line: line
        )
    }

    private func makeCoordinator(
        _ context: Context,
        port: RecordedPlatformActions
    ) -> BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: context.browser,
            downloadCenter: context.downloadCenter,
            spaceAccess: context.access,
            platformActions: port.platformActions
        )
    }

    private func makeContext(isProtected: Bool = false) -> Context {
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
            url: URL(fileURLWithPath: "/crest-sidebar-history"),
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
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open,
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
            filename: "Crest.dmg",
            createdAt: Date(timeIntervalSince1970: 1_700_000_004)
        )
        return Context(
            browser: browser,
            downloadCenter: BrowserDownloadCenter(ledger: ledger),
            downloadItemID: downloadItemID,
            access: BrowserSpaceAccessController(
                authenticator: AcceptingAuthenticator()
            ),
            source: source,
            destination: destination,
            archived: archived,
            history: history
        )
    }

    private func replaceProfile(of space: BrowserSpace, in browser: BrowserStore) {
        guard
            let index = browser.session.spaces.firstIndex(where: {
                $0.id == space.id
            })
        else {
            XCTFail("Expected the captured Space.")
            return
        }
        let current = browser.session.spaces[index]
        browser.session.spaces[index] = BrowserSpace(
            id: current.id,
            profile: BrowsingProfile(id: Self.uuid(7)),
            name: current.name,
            symbol: current.symbol,
            accent: current.accent,
            branding: current.branding,
            folders: current.folders,
            tabs: current.tabs,
            archivedTabs: current.archivedTabs,
            history: current.history,
            browsingPreferences: current.browsingPreferences,
            credentialPreferences: current.credentialPreferences,
            accessPolicy: current.accessPolicy,
            isSavedTabsExpanded: current.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: current.savedTabsExpansionModifiedAt,
            selectedTabID: current.selectedTabID
        )
    }

    private func downloadItem(profileID: UUID, id: UUID) -> BrowserDownloadItem {
        BrowserDownloadItem(
            id: id,
            profileID: profileID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_004),
            filename: "Crest.dmg",
            destinationURL: nil,
            progress: 0.5,
            state: .downloading,
            riskAssessment: nil
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x55,
                0x54, 0x49, 0x4C, 0x49, 0x54, 0x59, 0x00, finalByte
            ))
    }

    private struct Context {
        let browser: BrowserStore
        let downloadCenter: BrowserDownloadCenter
        let downloadItemID: UUID
        let access: BrowserSpaceAccessController
        let source: BrowserSpace
        let destination: BrowserSpace
        let archived: ArchivedTab
        let history: BrowserHistoryEntry
    }

    /// A stand-in for either shell's binding, so a guard can be tested by what
    /// it lets through rather than by what a particular shell does next.
    @MainActor
    private final class RecordedPlatformActions {
        var restoredTabs: [TabID] = []
        var openedURLs: [URL] = []
        var openedDownloads: [(item: BrowserDownloadItem, destination: BrowserUtilityDownloadDestination)] = []
        var canceledDownloads: [UUID] = []
        var clearedDownloads: [UUID] = []

        var platformActions: BrowserSidebarUtilityPlatformActions {
            BrowserSidebarUtilityPlatformActions(
                downloadDestinations: [.open, .revealInFinder],
                openHistoryEntry: { url, _ in self.openedURLs.append(url) },
                selectRestoredTab: { self.restoredTabs.append($0) },
                openFinishedDownload: { item, destination in
                    self.openedDownloads.append((item, destination))
                },
                cancelDownload: { self.canceledDownloads.append($0) },
                clearDownload: { self.clearedDownloads.append($0) }
            )
        }
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
