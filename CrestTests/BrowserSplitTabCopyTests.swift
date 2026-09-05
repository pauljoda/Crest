import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSplitTabCopyTests: XCTestCase {
    func testDurableParticipantsStayInPlaceAndSplitUsesIndependentCurrentCopies() throws {
        for sourcePlacement in [TabPlacement.pinned, .saved, .current] {
            for targetPlacement in [TabPlacement.pinned, .saved, .current] {
                let folder = BrowserFolder(title: "Research")
                let source = tab("Source", placement: sourcePlacement, folder: folder.id)
                let target = tab("Target", placement: targetPlacement, folder: folder.id)
                let store = store(tabs: [source, target], folders: [folder], selected: target.id)
                let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(store.selectedSpace))
                let originals = try XCTUnwrap(store.selectedSpace).tabs

                XCTAssertTrue(store.splitTabWithSelectedTab(source.id, matching: assignment))

                let space = try XCTUnwrap(store.selectedSpace)
                let selected = try XCTUnwrap(store.selectedTab)
                let group = try XCTUnwrap(space.splitGroup(containing: selected.id))
                let members = space.splitGroupMembers(of: group)
                XCTAssertEqual(members.map(\.title), [target.title, source.title])
                XCTAssertTrue(members.allSatisfy { $0.placement == .current && $0.folderID == nil })
                for original in originals where original.placement != .current {
                    XCTAssertEqual(space.tabs.first { $0.id == original.id }, original)
                    XCTAssertFalse(members.contains { $0.id == original.id })
                }
                XCTAssertEqual(
                    space.tabs.filter { $0.placement != .current }, originals.filter { $0.placement != .current })
                XCTAssertEqual(selected.url, source.url)
                XCTAssertNil(selected.savedURL)
                XCTAssertEqual(Set(space.tabs.map(\.id)).count, space.tabs.count)
                XCTAssertEqual(space.tabs.count, 2 + originals.filter { $0.placement != .current }.count)
                XCTAssertTrue(store.dissolveSplit(containing: selected.id, matching: assignment))
                for original in originals where original.placement != .current {
                    XCTAssertEqual(store.selectedSpace?.tabs.first { $0.id == original.id }, original)
                }
            }
        }
    }

    func testInvalidDurableSplitLeavesSessionAndPersistenceUntouched() throws {
        let source = tab("Source", placement: .saved)
        let target = tab("Target", placement: .pinned)
        let store = store(tabs: [source, target], selected: target.id)
        let space = try XCTUnwrap(store.selectedSpace)
        let original = store.session
        let item = BrowserTabDragItem(tabID: source.id, spaceID: space.id, profileID: space.profile.id)
        XCTAssertFalse(store.addTabToSplit(item, joining: source.id, at: nil))
        XCTAssertFalse(store.addTabToSplit(item, joining: TabID(), at: nil))
        XCTAssertFalse(
            store.addTabToSplit(
                BrowserTabDragItem(tabID: source.id, spaceID: space.id, profileID: UUID()),
                joining: target.id, at: nil
            ))
        XCTAssertEqual(store.session, original)
    }

    func testSavedDestinationGroupIsCopiedInOrderAndSurvivesSessionReload() throws {
        let folder = BrowserFolder(title: "Nested research")
        let groupID = SplitGroupID()
        var head = tab("Head", placement: .saved, folder: folder.id)
        var tail = tab("Tail", placement: .saved, folder: folder.id)
        head.splitGroupID = groupID
        tail.splitGroupID = groupID
        let source = tab("Pinned", placement: .pinned)
        let store = store(tabs: [source, head, tail], folders: [folder], selected: tail.id)
        let space = try XCTUnwrap(store.selectedSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        XCTAssertTrue(store.setSplitGroupTitle("Research pair", groupID: groupID, matching: assignment))
        let originals = try XCTUnwrap(store.selectedSpace)

        XCTAssertTrue(
            store.addTabToSplit(
                BrowserTabDragItem(tabID: source.id, spaceID: space.id, profileID: space.profile.id),
                joining: tail.id, at: 1
            ))

        let copiedGroup = try XCTUnwrap(
            store.selectedSpace?.splitGroup(containing: try XCTUnwrap(store.selectedTab).id))
        XCTAssertNotEqual(copiedGroup, groupID)
        XCTAssertEqual(
            store.selectedSpace?.splitGroupMembers(of: copiedGroup).map(\.title), ["Head", "Pinned", "Tail"])
        XCTAssertEqual(store.selectedSpace?.splitGroupMetadata(for: copiedGroup)?.customTitle, "Research pair")
        var restored = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(store.session))
        restored.repairRuntimeIntegrity()
        XCTAssertEqual(
            restored.selectedSpace?.splitGroupMembers(of: copiedGroup).map(\.id),
            store.selectedSpace?.splitGroupMembers(of: copiedGroup).map(\.id))
        let restoredOriginals = try JSONDecoder().decode(BrowserSpace.self, from: JSONEncoder().encode(originals))
        XCTAssertEqual(restored.selectedSpace?.tabs.filter { $0.placement != .current }, restoredOriginals.tabs)
        XCTAssertEqual(
            restored.selectedSpace?.splitGroupMetadata(for: groupID), originals.splitGroupMetadata(for: groupID))
    }

    func testFullGroupAndDraftRefuseLinkAndDurableCopiesWithoutMutation() throws {
        let groupID = SplitGroupID()
        let members = (0..<4).map { index -> BrowserTab in
            var member = tab("Member\(index)", placement: .saved)
            member.splitGroupID = groupID
            return member
        }
        let source = tab("Pinned", placement: .pinned)
        let draft = BrowserTab.startPage()
        let store = store(tabs: [source] + members + [draft], selected: members[0].id)
        let space = try XCTUnwrap(store.selectedSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let original = store.session
        let item = BrowserTabDragItem(tabID: source.id, spaceID: space.id, profileID: space.profile.id)
        XCTAssertFalse(store.addTabToSplit(item, joining: members[0].id, at: nil))
        XCTAssertFalse(store.addTabToSplit(item, joining: draft.id, at: nil))
        XCTAssertNil(
            store.openLinkInSplit(url: try XCTUnwrap(source.url), joining: members[0].id, matching: assignment))
        XCTAssertNil(store.openLinkInSplit(url: try XCTUnwrap(source.url), joining: draft.id, matching: assignment))
        XCTAssertEqual(store.session, original)
    }

    func testLinkIntoPinnedDestinationCopiesOnlyTheDestinationAndCommitsOnce() throws {
        let target = tab("Pinned", placement: .pinned)
        let store = store(tabs: [target], selected: target.id)
        let space = try XCTUnwrap(store.selectedSpace)
        let revision = store.sessionRevision
        let linkURL = try XCTUnwrap(URL(string: "https://crest.test/link"))
        let openedID = try XCTUnwrap(
            store.openLinkInSplit(
                url: linkURL, joining: target.id, matching: BrowserSpaceRuntimeAssignment(space: space)
            ))
        XCTAssertEqual(store.sessionRevision, revision + 1)
        XCTAssertEqual(store.selectedTab?.id, openedID)
        XCTAssertEqual(store.selectedTab?.url, linkURL)
        XCTAssertEqual(store.selectedSpace?.tabs.count, 3)
        XCTAssertEqual(store.selectedSpace?.pinnedTabs, [target])
    }

    func testRepeatingWithAnExistingCopyDoesNotCopyItAgain() throws {
        let target = tab("Open", placement: .current)
        let source = tab("Saved", placement: .saved)
        let store = store(tabs: [source, target], selected: target.id)
        let space = try XCTUnwrap(store.selectedSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        XCTAssertTrue(store.splitTabWithSelectedTab(source.id, matching: assignment))
        let copy = try XCTUnwrap(store.selectedTab)
        let original = store.session
        XCTAssertFalse(
            store.addTabToSplit(
                BrowserTabDragItem(tabID: copy.id, spaceID: space.id, profileID: space.profile.id),
                joining: target.id, at: nil
            ))
        XCTAssertEqual(store.session, original)
    }

    func testSyncRoundTripKeepsDurableOriginalsAndOpenFolderMembership() throws {
        let savedFolder = BrowserFolder(title: "Saved research")
        let currentFolder = BrowserFolder(title: "Open work", location: .current)
        let source = tab("Saved", placement: .saved, folder: savedFolder.id)
        var target = tab("Open", placement: .current)
        target.folderID = currentFolder.id
        let store = store(tabs: [source, target], folders: [savedFolder, currentFolder], selected: target.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(store.selectedSpace))
        var journal = BrowserSyncJournal(deviceID: UUID())
        try journal.stage(session: store.session)
        journal.markUploaded(journal.pendingRecordIDs)
        XCTAssertTrue(store.splitTabWithSelectedTab(source.id, matching: assignment))
        let copy = try XCTUnwrap(store.selectedTab)
        XCTAssertEqual(copy.folderID, currentFolder.id)
        try journal.stage(session: store.session)
        let materialized = try journal.materializedSession(applyingTo: store.session)
        let restored = try XCTUnwrap(materialized.selectedSpace)
        XCTAssertEqual(restored.tabs.map(\.id), store.selectedSpace?.tabs.map(\.id))
        XCTAssertEqual(restored.tabs.first { $0.id == source.id }?.folderID, savedFolder.id)
        XCTAssertEqual(restored.tabs.first { $0.id == source.id }?.savedURL, source.savedURL)
        XCTAssertEqual(restored.tabs.first { $0.id == copy.id }?.folderID, currentFolder.id)
        XCTAssertEqual(restored.tabs.first { $0.id == copy.id }?.splitGroupID, copy.splitGroupID)
        XCTAssertFalse(journal.pendingRecordIDs.contains(BrowserSyncRecordID(kind: .tab, value: source.id.rawValue)))
    }

    private func tab(_ title: String, placement: TabPlacement, folder: FolderID? = nil) -> BrowserTab {
        BrowserTab(
            title: title,
            url: URL(string: "https://crest.test/\(title)/child"),
            savedURL: placement == .current ? nil : URL(string: "https://crest.test/\(title)"),
            iconMode: .automatic,
            placement: placement,
            folderID: placement == .saved ? folder : nil
        )
    }

    private func store(tabs: [BrowserTab], folders: [BrowserFolder] = [], selected: TabID) -> BrowserStore {
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Work", symbol: "globe", accent: .teal, folders: folders,
            tabs: tabs, selectedTabID: selected)
        return BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence())
    }
}
