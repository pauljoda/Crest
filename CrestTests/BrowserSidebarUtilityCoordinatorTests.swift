import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarUtilityCoordinatorTests: XCTestCase {
    func testExactSelectedAssignmentRestoresArchiveAndOpensHistory() throws {
        let context = makeContext()
        let coordinator = makeCoordinator(context)
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
                $0.url == context.history.url
            }))
    }

    func testCapturedUtilityActionsRejectSelectionAndProfileChanges() throws {
        let selectionContext = makeContext()
        let selectionCoordinator = makeCoordinator(selectionContext)
        let selectionAssignment = BrowserSpaceRuntimeAssignment(
            space: selectionContext.source
        )
        selectionContext.browser.selectSpace(selectionContext.destination.id)

        selectionCoordinator.actions.restoreArchivedTab(
            selectionContext.archived.id,
            selectionAssignment
        )
        selectionCoordinator.actions.openHistoryEntry(
            selectionContext.history,
            selectionAssignment
        )
        XCTAssertEqual(
            try XCTUnwrap(
                selectionContext.browser.session.space(
                    id: selectionContext.source.id
                )
            ).archivedTabs.map(\.id),
            [selectionContext.archived.id]
        )
        XCTAssertFalse(
            try XCTUnwrap(
                selectionContext.browser.session.space(
                    id: selectionContext.source.id
                )
            ).tabs.contains(where: {
                $0.url == selectionContext.history.url
            })
        )

        let replacementContext = makeContext()
        let replacementCoordinator = makeCoordinator(replacementContext)
        let replacementAssignment = BrowserSpaceRuntimeAssignment(
            space: replacementContext.source
        )
        replaceProfile(of: replacementContext.source, in: replacementContext.browser)

        replacementCoordinator.actions.restoreArchivedTab(
            replacementContext.archived.id,
            replacementAssignment
        )
        replacementCoordinator.actions.openHistoryEntry(
            replacementContext.history,
            replacementAssignment
        )
        let replacement = try XCTUnwrap(
            replacementContext.browser.session.space(
                id: replacementContext.source.id
            )
        )
        XCTAssertEqual(replacement.archivedTabs.map(\.id), [replacementContext.archived.id])
        XCTAssertFalse(
            replacement.tabs.contains(where: {
                $0.url == replacementContext.history.url
            }))
    }

    func testCapturedUtilityActionsRejectLockedAndDeletingSpaces() throws {
        let lockedContext = makeContext(isProtected: true)
        let lockedCoordinator = makeCoordinator(lockedContext)
        let lockedAssignment = BrowserSpaceRuntimeAssignment(
            space: lockedContext.source
        )

        lockedCoordinator.actions.restoreArchivedTab(
            lockedContext.archived.id,
            lockedAssignment
        )
        lockedCoordinator.actions.openHistoryEntry(
            lockedContext.history,
            lockedAssignment
        )
        XCTAssertEqual(
            try XCTUnwrap(
                lockedContext.browser.session.space(id: lockedContext.source.id)
            ).archivedTabs.map(\.id),
            [lockedContext.archived.id]
        )
        XCTAssertFalse(
            try XCTUnwrap(
                lockedContext.browser.session.space(id: lockedContext.source.id)
            ).tabs.contains(where: {
                $0.url == lockedContext.history.url
            })
        )

        let deletingContext = makeContext()
        let deletingCoordinator = makeCoordinator(deletingContext)
        let deletingAssignment = BrowserSpaceRuntimeAssignment(
            space: deletingContext.source
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

        deletingCoordinator.actions.restoreArchivedTab(
            deletingContext.archived.id,
            deletingAssignment
        )
        deletingCoordinator.actions.openHistoryEntry(
            deletingContext.history,
            deletingAssignment
        )
        XCTAssertEqual(
            try XCTUnwrap(
                deletingContext.browser.session.space(
                    id: deletingContext.source.id
                )
            ).archivedTabs.map(\.id),
            [deletingContext.archived.id]
        )
        XCTAssertFalse(
            try XCTUnwrap(
                deletingContext.browser.session.space(
                    id: deletingContext.source.id
                )
            ).tabs.contains(where: {
                $0.url == deletingContext.history.url
            })
        )
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

    private func makeCoordinator(
        _ context: Context
    ) -> BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: context.browser,
            pages: context.pages,
            spaceAccess: context.access
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
        return Context(
            browser: browser,
            pages: BrowserPagePool(
                browsingMode: .privateBrowsing,
                usesEphemeralWebsiteDataStores: true
            ),
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
        let pages: BrowserPagePool
        let access: BrowserSpaceAccessController
        let source: BrowserSpace
        let destination: BrowserSpace
        let archived: ArchivedTab
        let history: BrowserHistoryEntry
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
