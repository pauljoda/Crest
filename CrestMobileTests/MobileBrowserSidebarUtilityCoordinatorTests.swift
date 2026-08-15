import Foundation
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserSidebarUtilityCoordinatorTests: XCTestCase {
    func testExactSelectedAssignmentRestoresArchiveAndOpensHistory() throws {
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
            ).archivedTabs.contains(where: { $0.id == context.archived.id })
        )
    }

    func testCapturedActionsRejectSelectionProfileAndLockChanges() throws {
        try assertActionsAreRejected { context in
            context.browser.selectSpace(context.destination.id)
        }
        try assertActionsAreRejected { context in
            self.replaceProfile(of: context.source, in: context.browser)
        }
        try assertActionsAreRejected(
            context: makeContext(isProtected: true),
            mutation: { _ in }
        )
    }

    func testCapturedActionsRejectDeletingSpace() throws {
        let context = makeContext()
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.source.id))
        defer { context.browser.family.finishDeletingSpace(context.source.id) }

        try assertActionsAreRejected(context: context, mutation: { _ in })
    }

    private func assertActionsAreRejected(
        context: Context? = nil,
        mutation: (Context) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let context = context ?? makeContext()
        var selectedTabs: [TabID] = []
        var openedURLs: [URL] = []
        let coordinator = makeCoordinator(
            context,
            selectTab: { selectedTabs.append($0) },
            openURL: { openedURLs.append($0) }
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        mutation(context)

        coordinator.actions.restoreArchivedTab(context.archived.id, assignment)
        coordinator.actions.openHistoryEntry(context.history, assignment)

        XCTAssertTrue(selectedTabs.isEmpty, file: file, line: line)
        XCTAssertTrue(openedURLs.isEmpty, file: file, line: line)
        XCTAssertEqual(
            try XCTUnwrap(
                context.browser.session.space(id: context.source.id)
            ).archivedTabs.map(\.id),
            [context.archived.id],
            file: file,
            line: line
        )
    }

    private func makeCoordinator(
        _ context: Context,
        selectTab: @escaping (TabID) -> Void,
        openURL: @escaping (URL) -> Void
    ) -> MobileBrowserSidebarUtilityCoordinator {
        MobileBrowserSidebarUtilityCoordinator(
            browser: context.browser,
            pages: context.pages,
            spaceAccess: context.access,
            selectTab: selectTab,
            openURL: openURL
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
            pages: MobileBrowserPageStore(
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
