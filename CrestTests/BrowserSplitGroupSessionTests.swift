import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSplitGroupSessionTests: XCTestCase {
    private let mutationDate = Date(timeIntervalSince1970: 1_000)

    func testMovingAMemberIntoAnEarlierSplitPreservesItsFormerSiblings() throws {
        let oldGroup = SplitGroupID()
        let target = makeTab("Target")
        let bystander = makeTab("Bystander")
        let siblings = [makeTab("Head", group: oldGroup), makeTab("Tail", group: oldGroup)]
        let member = makeTab("Moved Member", group: oldGroup)
        let store = makeStore(tabs: [target, bystander] + siblings + [member], selectedTabID: target.id)

        XCTAssertTrue(store.addTabToSplit(try dragItem(member.id, in: store), joining: target.id, at: 0))

        let updated = try XCTUnwrap(store.selectedSpace)
        XCTAssertEqual(updated.splitGroupMembers(of: oldGroup).map(\.id), siblings.map(\.id))
        let joinedGroup = try XCTUnwrap(updated.splitGroup(containing: target.id))
        XCTAssertNotEqual(joinedGroup, oldGroup)
        XCTAssertEqual(updated.splitGroupMembers(of: joinedGroup).map(\.id), [member.id, target.id])
        XCTAssertEqual(updated.tabs.first { $0.id == bystander.id }, bystander)
    }

    func testJoiningAnUngroupedTargetCreatesTheGroupAndFocusesTheJoiner() throws {
        let first = makeTab("First")
        let second = makeTab("Second")
        let third = makeTab("Third")
        let store = makeStore(tabs: [first, second, third], selectedTabID: first.id)

        XCTAssertTrue(store.addTabToSplit(try dragItem(third.id, in: store), joining: first.id, at: nil))

        let repaired = try XCTUnwrap(store.selectedSpace)
        XCTAssertEqual(repaired.tabs.map(\.id), [first.id, third.id, second.id])
        let groupID = try XCTUnwrap(repaired.splitGroup(containing: first.id))
        XCTAssertEqual(
            repaired.splitGroupMembers(of: groupID).map(\.id),
            [first.id, third.id]
        )
        XCTAssertEqual(
            store.selectedTabID(in: repaired.id),
            third.id,
            "Drop and context-menu callers rely on the joined tab taking focus."
        )
    }

    func testJoiningMarksPositionModifiedOnEveryMemberIncludingTheTarget() throws {
        let target = makeTab("Target")
        let joiner = makeTab("Joiner")
        let bystander = makeTab("Bystander")
        let store = makeStore(tabs: [target, joiner, bystander], selectedTabID: target.id)

        XCTAssertTrue(store.addTabToSplit(try dragItem(joiner.id, in: store), joining: target.id, at: nil))

        let repaired = try XCTUnwrap(store.selectedSpace)
        XCTAssertNotNil(
            repaired.tabs.first { $0.id == target.id }?.positionModifiedAt,
            "Membership rides the latestPosition merge win-set, so it needs a fresh stamp."
        )
        XCTAssertNotNil(repaired.tabs.first { $0.id == joiner.id }?.positionModifiedAt)
        XCTAssertNil(repaired.tabs.first { $0.id == bystander.id }?.positionModifiedAt)
    }

    func testMovingAMemberToAnotherSpaceClearsItsMembership() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let source = makeSpace(name: "Source", tabs: [head, tail])
        let resident = makeTab("Resident")
        let destination = makeSpace(name: "Destination", tabs: [resident])
        let store = BrowserStore(
            session: BrowserSession(spaces: [source, destination]),
            showing: source.id, tabs: [source.id: head.id, destination.id: resident.id]
        )

        XCTAssertTrue(store.moveTab(head.id, from: source.id, into: destination.id))

        let repairedDestination = try XCTUnwrap(store.session.space(id: destination.id))
        XCTAssertNil(repairedDestination.tabs.first { $0.id == head.id }?.splitGroupID)
        let repairedSource = try XCTUnwrap(store.session.space(id: source.id))
        XCTAssertEqual(
            repairedSource.tabs.first { $0.id == tail.id }?.splitGroupID,
            group
        )
        XCTAssertNil(
            repairedSource.splitGroup(containing: tail.id),
            "A run of one presents as a plain tab even while it keeps its stored ID."
        )
    }

    func testRemovingFromARunThatEndsItsSectionStaysInsideThatSection() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", placement: .saved, group: group)
        let middle = makeTab("Middle", placement: .saved, group: group)
        let tail = makeTab("Tail", placement: .saved, group: group)
        let current = makeTab("Current")
        let store = makeStore(tabs: [head, middle, tail, current], selectedTabID: head.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(store.selectedSpace))

        XCTAssertTrue(store.removeTabFromSplit(middle.id, matching: assignment))

        let repaired = try XCTUnwrap(store.selectedSpace)
        XCTAssertEqual(
            repaired.tabs.map(\.id),
            [head.id, tail.id, middle.id, current.id],
            "The anchor belongs to the next section, so the plan falls back to this section's end."
        )
        XCTAssertEqual(repaired.tabs[2].placement, .saved)
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [head.id, tail.id]
        )
    }

    // MARK: - Reordering cards inside a run

    func testMovingIsRefusedForNonMembersAndForSubRenderableRuns() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let plain = makeTab("Plain")
        let lone = makeTab("Lone", group: SplitGroupID())
        let store = makeStore(tabs: [head, tail, plain, lone], selectedTabID: head.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(store.selectedSpace))

        XCTAssertFalse(store.moveSplitMember(plain.id, by: -1, matching: assignment))
        XCTAssertFalse(
            store.moveSplitMember(lone.id, by: -1, matching: assignment),
            "A run too short to draw presents as a plain tab, so it reorders nothing."
        )
        XCTAssertFalse(store.moveSplitMember(TabID(), by: 1, matching: assignment))
        XCTAssertEqual(
            try XCTUnwrap(store.selectedSpace).tabs.map(\.id),
            [head.id, tail.id, plain.id, lone.id]
        )
    }

    func testMovingStampsOnlyTheCardsWhoseSlotChanged() throws {
        let group = SplitGroupID()
        let members = (0..<4).map { makeTab("Member \($0)", group: group) }
        let outsider = makeTab("Outsider")
        let store = makeStore(tabs: members + [outsider], selectedTabID: members[0].id)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(store.selectedSpace))

        XCTAssertTrue(store.moveSplitMember(members[3].id, toMemberIndex: 1, matching: assignment))

        let repaired = try XCTUnwrap(store.selectedSpace)
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [members[0].id, members[3].id, members[1].id, members[2].id]
        )
        XCTAssertNil(
            repaired.tabs.first { $0.id == members[0].id }?.positionModifiedAt,
            "The head kept slot 0, so it has no position opinion to upload."
        )
        for shifted in [members[3], members[1], members[2]] {
            XCTAssertNotNil(
                repaired.tabs.first { $0.id == shifted.id }?.positionModifiedAt,
                "Order rides the latestPosition merge win-set."
            )
        }
        XCTAssertNil(
            repaired.tabs.first { $0.id == outsider.id }?.positionModifiedAt
        )
    }

    func testMovingKeepsTheRunContiguousAndLeavesTheSelectionAlone() throws {
        let group = SplitGroupID()
        let before = makeTab("Before")
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let after = makeTab("After")
        let store = makeStore(tabs: [before, head, tail, after], selectedTabID: tail.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(store.selectedSpace))

        XCTAssertTrue(store.moveSplitMember(tail.id, by: -1, matching: assignment))

        let repaired = try XCTUnwrap(store.selectedSpace)
        XCTAssertEqual(
            repaired.tabs.map(\.id),
            [before.id, tail.id, head.id, after.id],
            "The permutation stays inside the run; its neighbours never move."
        )
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [tail.id, head.id]
        )
        XCTAssertEqual(
            store.selectedTabID(in: repaired.id),
            tail.id,
            "Reordering the cards does not change which one the chrome speaks for."
        )
    }

    func testTheStoreRefusesToMoveACardInAnUnselectedSpace() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let selected = makeSpace(name: "Selected", tabs: [makeTab("Only")])
        let other = makeSpace(name: "Other", tabs: [head, tail])
        let store = BrowserStore(
            session: BrowserSession(spaces: [selected, other]),
            showing: selected.id, tabs: [other.id: head.id]
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: other)

        XCTAssertFalse(store.canMoveSplitMember(head.id, by: 1, matching: assignment))
        XCTAssertFalse(store.moveSplitMember(head.id, by: 1, matching: assignment))
        XCTAssertEqual(
            store.session.space(id: other.id)?.tabs.map(\.id),
            [head.id, tail.id]
        )
    }

    func testClosingACardDownToOneMemberDissolvesTheGroupAndArchivesItUngrouped() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let store = makeStore(tabs: [head, tail], selectedTabID: head.id)
        let spaceID = store.selectedSpaceID

        XCTAssertTrue(store.closeTab(tail.id, in: spaceID))

        let repaired = try XCTUnwrap(store.session.space(id: spaceID))
        XCTAssertEqual(repaired.tabs.map(\.id), [head.id])
        XCTAssertNil(repaired.tabs[0].splitGroupID)
        XCTAssertNotNil(repaired.tabs[0].positionModifiedAt)
        XCTAssertNil(
            repaired.archivedTabs.last?.tab.splitGroupID,
            "An archived tab leaves its split behind."
        )
    }

    func testClosingOneOfThreeKeepsTheRemainingGroup() throws {
        let group = SplitGroupID()
        let members = (0..<3).map { makeTab("Member \($0)", group: group) }
        let store = makeStore(tabs: members, selectedTabID: members[0].id)
        let spaceID = store.selectedSpaceID

        XCTAssertTrue(store.closeTab(members[1].id, in: spaceID))

        let repaired = try XCTUnwrap(store.session.space(id: spaceID))
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [members[0].id, members[2].id],
            "Removing a tab closes the gap, so the survivors stay contiguous."
        )
    }

    func testRepairKeepsALoneMemberAndItsPositionTimestamp() throws {
        let group = SplitGroupID()
        var lone = makeTab("Lone", group: group)
        lone.markPositionModified(at: mutationDate)
        let space = makeSpace(tabs: [lone])
        var session = BrowserSession(spaces: [space])

        session = try session.openedAsSeed()

        let repaired = try XCTUnwrap(session.spaces.first)
        XCTAssertEqual(repaired.tabs[0].splitGroupID, group)
        XCTAssertEqual(repaired.tabs[0].positionModifiedAt, mutationDate)
        XCTAssertTrue(repaired.liveSplitGroupIDs.isEmpty)
    }

    func testMovingAGroupRelocatesItsMembersAsAnOrderedBlock() throws {
        let group = SplitGroupID()
        let saved = makeTab("Saved", placement: .saved)
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let trailing = makeTab("Trailing")
        let store = makeStore(tabs: [saved, head, tail, trailing], selectedTabID: head.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(store.selectedSpace))

        XCTAssertTrue(store.moveSplitGroup(group, matching: assignment, to: .saved))

        let repaired = try XCTUnwrap(store.selectedSpace)
        XCTAssertEqual(
            repaired.tabs.map(\.id),
            [saved.id, head.id, tail.id, trailing.id]
        )
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [head.id, tail.id]
        )
        XCTAssertTrue(
            repaired.splitGroupMembers(of: group).allSatisfy { $0.placement == .saved }
        )
    }

    func testTheStoreRefusesToJoinATabFromAnotherSpace() throws {
        let target = makeTab("Target")
        let selected = makeSpace(name: "Selected", tabs: [target])
        let foreign = makeTab("Foreign")
        let other = makeSpace(name: "Other", tabs: [foreign])
        let store = BrowserStore(
            session: BrowserSession(spaces: [selected, other]),
            showing: selected.id, tabs: [selected.id: target.id, other.id: foreign.id]
        )

        XCTAssertFalse(
            store.addTabToSplit(
                BrowserTabDragItem(
                    tabID: foreign.id,
                    spaceID: other.id,
                    profileID: other.profile.id
                ),
                joining: target.id,
                at: nil
            )
        )
        XCTAssertNil(store.selectedSpace?.tabs.first?.splitGroupID)
    }

    func testTheStoreJoinsRemovesAndDissolvesInsideTheSelectedSpace() throws {
        let target = makeTab("Target")
        let joiner = makeTab("Joiner")
        let extra = makeTab("Extra")
        let space = makeSpace(tabs: [target, joiner, extra])
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = makeStore(space: space, selectedTabID: target.id)
        let item = BrowserTabDragItem(
            tabID: joiner.id,
            spaceID: space.id,
            profileID: space.profile.id
        )

        XCTAssertTrue(store.addTabToSplit(item, joining: target.id, at: nil))
        let grouped = try XCTUnwrap(store.selectedSpace)
        let groupID = try XCTUnwrap(grouped.splitGroup(containing: target.id))
        XCTAssertEqual(
            grouped.splitGroupMembers(of: groupID).map(\.id),
            [target.id, joiner.id]
        )

        let extraItem = BrowserTabDragItem(
            tabID: extra.id,
            spaceID: space.id,
            profileID: space.profile.id
        )
        XCTAssertTrue(store.addTabToSplit(extraItem, joining: target.id, at: nil))
        XCTAssertTrue(store.removeTabFromSplit(extra.id, matching: assignment))
        XCTAssertEqual(
            store.selectedSpace?.splitGroupMembers(of: groupID).map(\.id),
            [target.id, joiner.id]
        )

        XCTAssertTrue(store.dissolveSplit(containing: target.id, matching: assignment))
        let separated = try XCTUnwrap(store.selectedSpace)
        XCTAssertTrue(separated.tabs.allSatisfy { $0.splitGroupID == nil })
        XCTAssertFalse(store.dissolveSplit(containing: target.id, matching: assignment))
    }

    // MARK: - "Split with Current Tab" and "Open Link in Split View"

    func testSplittingWithTheCurrentTabJoinsTheSubjectAndFocusesIt() throws {
        let selected = makeTab("Selected")
        let subject = makeTab("Subject", placement: .pinned)
        let space = makeSpace(tabs: [selected, subject])
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = makeStore(space: space, selectedTabID: selected.id)

        XCTAssertTrue(
            store.canSplitTabWithSelectedTab(subject.id, matching: assignment),
            "A pinned subject contributes an independent Open copy."
        )
        XCTAssertTrue(
            store.splitTabWithSelectedTab(subject.id, matching: assignment)
        )

        let grouped = try XCTUnwrap(store.selectedSpace)
        let groupID = try XCTUnwrap(grouped.splitGroup(containing: selected.id))
        let copied = try XCTUnwrap(store.selectedTab)
        XCTAssertNotEqual(copied.id, subject.id)
        XCTAssertEqual(copied.url, subject.url)
        XCTAssertEqual(
            grouped.splitGroupMembers(of: groupID).map(\.id),
            [selected.id, copied.id]
        )
        XCTAssertEqual(
            grouped.tabs.first { $0.id == subject.id }?.placement,
            .pinned
        )
        XCTAssertEqual(store.selectedTabID(in: space.id), copied.id)
    }

    func testSplittingWithTheCurrentTabIsRefusedForSelfSiblingsAndFullGroups()
        throws
    {
        let group = SplitGroupID()
        let members = (1...4).map { makeTab("Member \($0)", group: group) }
        let outsider = makeTab("Outsider")
        let space = makeSpace(tabs: members + [outsider])
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = makeStore(space: space, selectedTabID: members[0].id)

        XCTAssertFalse(
            store.canSplitTabWithSelectedTab(members[0].id, matching: assignment),
            "A tab cannot split with itself."
        )
        XCTAssertFalse(
            store.canSplitTabWithSelectedTab(members[1].id, matching: assignment),
            "A sibling is already in the presented split."
        )
        XCTAssertFalse(
            store.canSplitTabWithSelectedTab(outsider.id, matching: assignment),
            "A full group takes no more members."
        )
        XCTAssertFalse(
            store.splitTabWithSelectedTab(outsider.id, matching: assignment)
        )
    }

    func testOpeningALinkInSplitViewCreatesTheTabAndGroupsItWithTheTarget()
        throws
    {
        let target = makeTab("Target")
        let space = makeSpace(tabs: [target])
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = makeStore(space: space, selectedTabID: target.id)
        let link = try XCTUnwrap(URL(string: "https://example.com/linked"))

        let openedID = try XCTUnwrap(
            store.openLinkInSplit(
                url: link,
                joining: target.id,
                matching: assignment
            )
        )

        let grouped = try XCTUnwrap(store.selectedSpace)
        let groupID = try XCTUnwrap(grouped.splitGroup(containing: target.id))
        XCTAssertEqual(
            grouped.splitGroupMembers(of: groupID).map(\.id),
            [target.id, openedID]
        )
        XCTAssertEqual(
            grouped.tabs.first { $0.id == openedID }?.url,
            link
        )
        XCTAssertEqual(store.selectedTabID(in: space.id), openedID)
    }

    func testSplitGroupCustomizationPersistsEveryFieldAndFullEmojiCluster()
        throws
    {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail])
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = makeStore(space: space, selectedTabID: head.id)
        let tint = BrowserSpaceBrandColor(red: 0.16, green: 0.48, blue: 0.82)
        let emoji = "👨🏽‍💻"

        XCTAssertTrue(store.setSplitGroupTitle("  Research Pair  ", groupID: group, matching: assignment))
        XCTAssertTrue(store.setSplitGroupEmojiIcon(emoji, groupID: group, matching: assignment))
        XCTAssertTrue(store.setSplitGroupTint(tint, groupID: group, matching: assignment))

        let decoded = try JSONDecoder().decode(
            BrowserSession.self,
            from: JSONEncoder().encode(store.session)
        )
        let metadata = try XCTUnwrap(
            decoded.space(id: space.id)?.splitGroupMetadata(for: group)
        )
        XCTAssertEqual(metadata.displayTitle, "Research Pair")
        XCTAssertEqual(metadata.emojiIcon, emoji)
        XCTAssertEqual(metadata.tint, tint)
        XCTAssertNotNil(metadata.titleModifiedAt)
        XCTAssertNotNil(metadata.iconModifiedAt)
        XCTAssertNotNil(metadata.tintModifiedAt)
    }

    func testDissolvingAGroupRemovesItsDurableCustomization() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail])
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = makeStore(space: space, selectedTabID: head.id)
        XCTAssertTrue(store.setSplitGroupTitle("Temporary Pair", groupID: group, matching: assignment))

        XCTAssertTrue(store.removeTabFromSplit(tail.id, matching: assignment))

        let repaired = try XCTUnwrap(store.session.space(id: space.id))
        XCTAssertNil(repaired.splitGroupMetadata(for: group))
        XCTAssertTrue(repaired.splitGroups.isEmpty)
    }

    func testRepairRetainsMetadataWhileOnlyOneSyncedMemberHasArrived() throws {
        let group = SplitGroupID()
        let lone = makeTab("First Arrival", group: group)
        let metadata = BrowserSplitGroupMetadata(
            id: group,
            customTitle: "Synced Pair",
            titleModifiedAt: mutationDate
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [lone],
            splitGroups: [metadata]
        )

        let session = BrowserSession(spaces: [space])

        XCTAssertEqual(
            try XCTUnwrap(session.space(id: space.id)).splitGroups,
            [metadata],
            "Runtime repair cannot erase metadata before the remaining CloudKit tab records arrive."
        )
    }

    func testLegacySpaceWithoutSplitMetadataDecodesWithAnEmptyCollection()
        throws
    {
        let tab = makeTab("Legacy")
        let space = makeSpace(tabs: [tab])
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(space)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "splitGroups")

        let decoded = try JSONDecoder().decode(
            BrowserSpace.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(decoded.splitGroups.isEmpty)
    }

    private func makeStore(
        folders: [BrowserFolder] = [],
        tabs: [BrowserTab],
        selectedTabID: TabID?
    ) -> BrowserStore {
        makeStore(space: makeSpace(folders: folders, tabs: tabs), selectedTabID: selectedTabID)
    }

    /// A window showing `space` on `selectedTabID`.
    private func makeStore(space: BrowserSpace, selectedTabID: TabID?) -> BrowserStore {
        BrowserStore(
            session: BrowserSession(spaces: [space]),
            showing: space.id, tabs: selectedTabID.map { [space.id: $0] } ?? [:]
        )
    }

    private func dragItem(_ tabID: TabID, in store: BrowserStore) throws -> BrowserTabDragItem {
        let space = try XCTUnwrap(store.selectedSpace)
        return BrowserTabDragItem(tabID: tabID, spaceID: space.id, profileID: space.profile.id)
    }

    private func makeSpace(
        name: String = "Work",
        folders: [BrowserFolder] = [],
        tabs: [BrowserTab]
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: folders,
            tabs: tabs
        )
    }

    private func makeTab(
        _ title: String,
        placement: TabPlacement = .current,
        folderID: FolderID? = nil,
        group: SplitGroupID? = nil
    ) -> BrowserTab {
        BrowserTab(
            title: title,
            url: URL(string: "https://example.com/\(title.replacingOccurrences(of: " ", with: "-"))"),
            placement: placement,
            folderID: folderID,
            splitGroupID: group,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
