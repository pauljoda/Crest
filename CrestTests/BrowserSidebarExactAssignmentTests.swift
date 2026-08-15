import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarExactAssignmentTests: XCTestCase {
    func testCapturedTabCloseRejectsAReplacementBrowsingProfile() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        replaceProfile(of: context.source, in: context.store)

        XCTAssertFalse(
            context.store.closeTab(
                context.sourceTab.id,
                matching: assignment
            )
        )
        XCTAssertTrue(
            try XCTUnwrap(context.store.session.space(id: context.source.id))
                .contains(context.sourceTab.id)
        )
    }

    func testCapturedTabRenameRejectsAReplacementBrowsingProfile() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        replaceProfile(of: context.source, in: context.store)

        XCTAssertFalse(
            context.store.setTabCustomTitle(
                "Replacement title",
                for: context.sourceTab.id,
                matching: assignment
            )
        )
        XCTAssertNil(
            try XCTUnwrap(context.store.session.space(id: context.source.id))
                .tabs.first(where: { $0.id == context.sourceTab.id })?
                .customTitle
        )
    }

    func testLiveTabDropRejectsAReplacementDestinationProfile() throws {
        let context = makeContext()
        let item = dragItem(for: context.sourceTab, in: context.source)
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        context.store.selectSpace(context.destination.id)
        replaceProfile(of: context.destination, in: context.store)

        XCTAssertFalse(
            context.store.moveTab(
                item,
                to: .saved,
                matching: destinationAssignment
            )
        )
        assertTab(
            context.sourceTab.id,
            staysIn: context.source.id,
            outside: context.destination.id,
            store: context.store
        )
    }

    func testLiveTabDropDoesNotFollowAChangedSelectedSpace() throws {
        let context = makeContext()
        let item = dragItem(for: context.sourceTab, in: context.source)
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        context.store.selectSpace(context.destination.id)
        context.store.selectSpace(context.source.id)

        XCTAssertFalse(
            context.store.moveTab(
                item,
                to: .saved,
                matching: destinationAssignment
            )
        )
        assertTab(
            context.sourceTab.id,
            staysIn: context.source.id,
            outside: context.destination.id,
            store: context.store
        )
    }

    func testLiveTabDropRejectsADeletedRenderedFolder() throws {
        let context = makeContext()
        let item = dragItem(for: context.sourceTab, in: context.source)
        context.store.selectSpace(context.destination.id)
        let assignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        let folderID = try XCTUnwrap(
            context.store.addFolder(
                title: "Rendered target",
                matching: assignment
            )
        )
        XCTAssertTrue(
            context.store.deleteFolder(folderID, matching: assignment)
        )

        XCTAssertFalse(
            context.store.moveTab(
                item,
                to: .saved,
                folderID: folderID,
                matching: assignment
            )
        )
        assertTab(
            context.sourceTab.id,
            staysIn: context.source.id,
            outside: context.destination.id,
            store: context.store
        )
    }

    func testLiveTabDropAcceptsExactSourceAndDestinationAssignments() throws {
        let context = makeContext()
        let item = dragItem(for: context.sourceTab, in: context.source)
        context.store.selectSpace(context.destination.id)
        let assignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        let folderID = try XCTUnwrap(
            context.store.addFolder(
                title: "Exact target",
                matching: assignment
            )
        )

        XCTAssertTrue(
            context.store.moveTab(
                item,
                to: .saved,
                folderID: folderID,
                matching: assignment
            )
        )
        let movedTab = try XCTUnwrap(
            context.store.session.space(id: context.destination.id)?
                .tabs.first(where: { $0.id == context.sourceTab.id })
        )
        XCTAssertEqual(movedTab.placement, .saved)
        XCTAssertEqual(movedTab.folderID, folderID)
        XCTAssertFalse(
            try XCTUnwrap(context.store.session.space(id: context.source.id))
                .contains(context.sourceTab.id)
        )
    }

    func testStaleFolderDragRejectsAReplacementBrowsingProfile() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let folderID = try XCTUnwrap(
            context.store.addFolder(
                title: "Captured folder",
                matching: assignment
            )
        )
        let item = BrowserFolderDragItem(
            folderID: folderID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
        replaceProfile(of: context.source, in: context.store)

        XCTAssertFalse(
            context.store.moveFolder(
                item,
                matching: assignment,
                into: nil
            )
        )
        XCTAssertTrue(
            try XCTUnwrap(context.store.session.space(id: context.source.id))
                .folders.contains(where: { $0.id == folderID })
        )
    }

    func testCapturedFolderActionsRejectADeletingSpace() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let folderID = try XCTUnwrap(
            context.store.addFolder(
                title: "Captured folder",
                matching: assignment
            )
        )
        XCTAssertTrue(context.store.family.beginDeletingSpace(context.source.id))
        defer { context.store.family.finishDeletingSpace(context.source.id) }

        XCTAssertFalse(
            context.store.renameFolder(
                folderID,
                matching: assignment,
                title: "Rejected"
            )
        )
        XCTAssertNil(
            context.store.addFolder(
                title: "Rejected child",
                parentID: folderID,
                matching: assignment
            )
        )
        XCTAssertFalse(
            context.store.deleteFolder(folderID, matching: assignment)
        )
    }

    func testFolderDropRejectsAStaleRenderedSibling() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let movedFolderID = try XCTUnwrap(
            context.store.addFolder(
                title: "Moved folder",
                matching: assignment
            )
        )
        let siblingID = try XCTUnwrap(
            context.store.addFolder(
                title: "Rendered sibling",
                matching: assignment
            )
        )
        let item = BrowserFolderDragItem(
            folderID: movedFolderID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
        XCTAssertTrue(
            context.store.deleteFolder(siblingID, matching: assignment)
        )

        XCTAssertFalse(
            context.store.moveFolder(
                item,
                matching: assignment,
                into: nil,
                before: siblingID
            )
        )
        XCTAssertEqual(
            context.store.session.space(id: context.source.id)?
                .folders.first(where: { $0.id == movedFolderID })?
                .parentID,
            nil
        )
    }

    func testClearHistoryConfirmationRejectsSelectionChange() throws {
        let context = makeContext()
        let access = BrowserSpaceAccessController(
            authenticator: AcceptingAuthenticator()
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let historyURL = try XCTUnwrap(
            URL(string: "https://sidebar-history.crest.test/selection")
        )
        XCTAssertTrue(
            context.store.recordVisit(
                url: historyURL,
                title: "Selection",
                matching: assignment
            )
        )
        let confirmation = try XCTUnwrap(
            BrowserSidebarSpacePresentationPolicy.clearHistoryConfirmation(
                for: context.source,
                in: context.store,
                accessController: access
            )
        )
        context.store.selectSpace(context.destination.id)

        XCTAssertFalse(
            BrowserSidebarSpacePresentationPolicy.isLive(
                confirmation,
                in: context.store,
                accessController: access
            )
        )
        XCTAssertFalse(
            BrowserSidebarSpacePresentationPolicy.clearHistory(
                confirmation,
                in: context.store,
                accessController: access
            )
        )
        XCTAssertEqual(
            context.store.session.space(id: context.source.id)?.history.count,
            1
        )
    }

    func testClearHistoryConfirmationRejectsRelockedSpace() async throws {
        let context = makeContext(sourceIsProtected: true)
        let access = BrowserSpaceAccessController(
            authenticator: AcceptingAuthenticator()
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let historyURL = try XCTUnwrap(
            URL(string: "https://sidebar-history.crest.test/relock")
        )
        XCTAssertTrue(
            context.store.recordVisit(
                url: historyURL,
                title: "Relock",
                matching: assignment
            )
        )
        let didUnlock = await access.unlock(context.source)
        XCTAssertTrue(didUnlock)
        let confirmation = try XCTUnwrap(
            BrowserSidebarSpacePresentationPolicy.clearHistoryConfirmation(
                for: context.source,
                in: context.store,
                accessController: access
            )
        )
        access.lock(context.source.id)

        XCTAssertFalse(
            BrowserSidebarSpacePresentationPolicy.clearHistory(
                confirmation,
                in: context.store,
                accessController: access
            )
        )
        XCTAssertEqual(
            context.store.session.space(id: context.source.id)?.history.count,
            1
        )
    }

    private func makeContext(sourceIsProtected: Bool = false) -> (
        store: BrowserStore,
        source: BrowserSpace,
        destination: BrowserSpace,
        sourceTab: BrowserTab
    ) {
        let sourceTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(1)),
            title: "Source tab",
            url: nil,
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let destinationTab = BrowserTab.startPage(
            id: TabID(rawValue: fixedUUID(2)),
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let source = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(3)),
            profile: BrowsingProfile(id: fixedUUID(4)),
            name: "Source",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: [sourceTab],
            accessPolicy: sourceIsProtected
                ? .deviceOwnerAuthentication
                : .open,
            selectedTabID: sourceTab.id
        )
        let destination = BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(5)),
            profile: BrowsingProfile(id: fixedUUID(6)),
            name: "Destination",
            symbol: "2.circle",
            accent: .rose,
            folders: [],
            tabs: [destinationTab],
            selectedTabID: destinationTab.id
        )
        let store = BrowserStore(
            session: BrowserSession(
                spaces: [source, destination],
                selectedSpaceID: source.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        return (store, source, destination, sourceTab)
    }

    private func dragItem(
        for tab: BrowserTab,
        in space: BrowserSpace
    ) -> BrowserTabDragItem {
        BrowserTabDragItem(
            tabID: tab.id,
            spaceID: space.id,
            profileID: space.profile.id
        )
    }

    private func replaceProfile(
        of space: BrowserSpace,
        in store: BrowserStore
    ) {
        guard let current = store.session.space(id: space.id) else {
            XCTFail("Expected the captured Space to remain in the session.")
            return
        }
        let replacement = BrowserSpace(
            id: current.id,
            profile: BrowsingProfile(id: fixedUUID(7)),
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
        guard
            let index = store.session.spaces.firstIndex(where: {
                $0.id == space.id
            })
        else {
            XCTFail("Expected the captured Space to remain in the session.")
            return
        }
        store.session.spaces[index] = replacement
    }

    private func fixedUUID(_ suffix: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x2D,
                0x45, 0x58, 0x41, 0x43, 0x54, 0x00, 0x00, suffix
            )
        )
    }

    private func assertTab(
        _ tabID: TabID,
        staysIn sourceID: SpaceID,
        outside destinationID: SpaceID,
        store: BrowserStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            store.session.space(id: sourceID)?.contains(tabID) == true,
            file: file,
            line: line
        )
        XCTAssertFalse(
            store.session.space(id: destinationID)?.contains(tabID) == true,
            file: file,
            line: line
        )
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
