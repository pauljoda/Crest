import Foundation
import XCTest

@testable import Crest

final class BrowserSplitGroupSessionTests: XCTestCase {
    private let mutationDate = Date(timeIntervalSince1970: 1_000)

    func testJoiningAnUngroupedTargetCreatesTheGroupAndFocusesTheJoiner() throws {
        let first = makeTab("First")
        let second = makeTab("Second")
        let third = makeTab("Third")
        let space = makeSpace(tabs: [first, second, third], selectedTabID: first.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.addTabToSplit(
                third.id,
                joining: first.id,
                at: nil,
                in: space.id,
                at: mutationDate
            )
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(repaired.tabs.map(\.id), [first.id, third.id, second.id])
        let groupID = try XCTUnwrap(repaired.splitGroup(containing: first.id))
        XCTAssertEqual(
            repaired.splitGroupMembers(of: groupID).map(\.id),
            [first.id, third.id]
        )
        XCTAssertEqual(
            repaired.selectedTabID,
            third.id,
            "Drop and context-menu callers rely on the joined tab taking focus."
        )
    }

    func testAMemberIndexPlacesTheJoinerInThatSlot() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let joiner = makeTab("Joiner")
        let space = makeSpace(tabs: [head, tail, joiner], selectedTabID: head.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.addTabToSplit(
                joiner.id,
                joining: head.id,
                at: 1,
                in: space.id,
                at: mutationDate
            )
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [head.id, joiner.id, tail.id]
        )
    }

    func testJoiningMarksPositionModifiedOnEveryMemberIncludingTheTarget() throws {
        let target = makeTab("Target")
        let joiner = makeTab("Joiner")
        let bystander = makeTab("Bystander")
        let space = makeSpace(tabs: [target, joiner, bystander], selectedTabID: target.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.addTabToSplit(
                joiner.id,
                joining: target.id,
                at: nil,
                in: space.id,
                at: mutationDate
            )
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(
            repaired.tabs.first { $0.id == target.id }?.positionModifiedAt,
            mutationDate,
            "Membership rides the latestPosition merge win-set, so it needs a fresh stamp."
        )
        XCTAssertEqual(
            repaired.tabs.first { $0.id == joiner.id }?.positionModifiedAt,
            mutationDate
        )
        XCTAssertNil(repaired.tabs.first { $0.id == bystander.id }?.positionModifiedAt)
    }

    func testJoiningIsRefusedWhenTheRunIsAlreadyAtCap() throws {
        let group = SplitGroupID()
        let members = (0..<BrowserSplitGroupPolicy.maximumMembers).map {
            makeTab("Member \($0)", group: group)
        }
        let joiner = makeTab("Joiner")
        let space = makeSpace(tabs: members + [joiner], selectedTabID: members[0].id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertFalse(
            session.addTabToSplit(
                joiner.id,
                joining: members[0].id,
                at: nil,
                in: space.id,
                at: mutationDate
            )
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(repaired.tabs.map(\.id), (members + [joiner]).map(\.id))
        XCTAssertNil(repaired.tabs.last?.splitGroupID)
    }

    func testJoiningIsRefusedForTheTargetItselfAndForAbsentTabs() {
        let target = makeTab("Target")
        let space = makeSpace(tabs: [target], selectedTabID: target.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertFalse(
            session.addTabToSplit(
                target.id,
                joining: target.id,
                at: nil,
                in: space.id,
                at: mutationDate
            )
        )
        XCTAssertFalse(
            session.addTabToSplit(
                TabID(),
                joining: target.id,
                at: nil,
                in: space.id,
                at: mutationDate
            )
        )
    }

    func testAPinnedJoinerLeavesThePinnedSectionThroughThePlacementPlan() throws {
        let pinned = makeTab("Pinned", placement: .pinned)
        let target = makeTab("Target")
        let trailing = makeTab("Trailing")
        let space = makeSpace(tabs: [pinned, target, trailing], selectedTabID: target.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.addTabToSplit(
                pinned.id,
                joining: target.id,
                at: nil,
                in: space.id,
                at: mutationDate
            )
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        let joined = try XCTUnwrap(repaired.tabs.first { $0.id == pinned.id })
        XCTAssertEqual(joined.placement, .current)
        let groupID = try XCTUnwrap(repaired.splitGroup(containing: target.id))
        XCTAssertEqual(
            repaired.splitGroupMembers(of: groupID).map(\.id),
            [target.id, pinned.id]
        )
    }

    func testPinningAMemberClearsItsMembership() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail], selectedTabID: head.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.setExtensionTabPinned(
                true,
                tabID: head.id,
                in: space.id,
                at: mutationDate
            )
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertNil(repaired.tabs.first { $0.id == head.id }?.splitGroupID)
        XCTAssertEqual(
            repaired.tabs.first { $0.id == tail.id }?.splitGroupID,
            group,
            "Repair keeps the survivor's ID; only a user mutation dissolves a singleton."
        )
    }

    func testMovingAMemberToAnotherSpaceClearsItsMembership() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let source = makeSpace(name: "Source", tabs: [head, tail], selectedTabID: head.id)
        let resident = makeTab("Resident")
        let destination = makeSpace(
            name: "Destination",
            tabs: [resident],
            selectedTabID: resident.id
        )
        var session = BrowserSession(
            spaces: [source, destination],
            selectedSpaceID: source.id
        )

        XCTAssertTrue(
            session.moveTab(
                head.id,
                from: source.id,
                into: destination.id,
                at: mutationDate
            )
        )

        let repairedDestination = try XCTUnwrap(session.space(id: destination.id))
        XCTAssertNil(repairedDestination.tabs.first { $0.id == head.id }?.splitGroupID)
        let repairedSource = try XCTUnwrap(session.space(id: source.id))
        XCTAssertEqual(
            repairedSource.tabs.first { $0.id == tail.id }?.splitGroupID,
            group
        )
        XCTAssertNil(
            repairedSource.splitGroup(containing: tail.id),
            "A run of one presents as a plain tab even while it keeps its stored ID."
        )
    }

    func testRemovingTheOtherMemberDissolvesTheGroup() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail], selectedTabID: head.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.removeTabFromSplit(tail.id, in: space.id, at: mutationDate)
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(
            repaired.tabs.map(\.id),
            [head.id, tail.id],
            "A two-card group dissolves anyway, so nothing is relocated."
        )
        XCTAssertNil(repaired.tabs[0].splitGroupID)
        XCTAssertNil(repaired.tabs[1].splitGroupID)
        XCTAssertEqual(repaired.tabs[0].positionModifiedAt, mutationDate)
        XCTAssertEqual(repaired.tabs[1].positionModifiedAt, mutationDate)
    }

    func testRemovingAMiddleMemberSlidesItPastTheRunAndKeepsTheSurvivorsGrouped() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let middle = makeTab("Middle", group: group)
        let tail = makeTab("Tail", group: group)
        let outsider = makeTab("Outsider")
        let space = makeSpace(
            tabs: [head, middle, tail, outsider],
            selectedTabID: head.id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.removeTabFromSplit(middle.id, in: space.id, at: mutationDate)
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(
            repaired.tabs.map(\.id),
            [head.id, tail.id, middle.id, outsider.id],
            "The departing tab lands directly after the members it left behind."
        )
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [head.id, tail.id]
        )
        XCTAssertNil(repaired.tabs[2].splitGroupID)
        XCTAssertEqual(repaired.tabs[2].positionModifiedAt, mutationDate)
    }

    func testRemovingTheHeadMemberKeepsTheSurvivorsGrouped() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let middle = makeTab("Middle", group: group)
        let tail = makeTab("Tail", group: group)
        let outsider = makeTab("Outsider")
        let space = makeSpace(
            tabs: [head, middle, tail, outsider],
            selectedTabID: head.id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.removeTabFromSplit(head.id, in: space.id, at: mutationDate)
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(
            repaired.tabs.map(\.id),
            [middle.id, tail.id, head.id, outsider.id]
        )
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [middle.id, tail.id]
        )
    }

    func testRemovingTheTailMemberMovesNothing() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let middle = makeTab("Middle", group: group)
        let tail = makeTab("Tail", group: group)
        let outsider = makeTab("Outsider")
        let space = makeSpace(
            tabs: [head, middle, tail, outsider],
            selectedTabID: head.id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.removeTabFromSplit(tail.id, in: space.id, at: mutationDate)
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(
            repaired.tabs.map(\.id),
            [head.id, middle.id, tail.id, outsider.id],
            "The last member is already past the run; relocating it would reorder for nothing."
        )
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [head.id, middle.id]
        )
    }

    func testRemovingFromARunThatEndsTheTabListUsesTheEndOfSectionAnchor() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let middle = makeTab("Middle", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, middle, tail], selectedTabID: head.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.removeTabFromSplit(middle.id, in: space.id, at: mutationDate)
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(repaired.tabs.map(\.id), [head.id, tail.id, middle.id])
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [head.id, tail.id]
        )
    }

    func testRemovingFromARunThatEndsItsSectionStaysInsideThatSection() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", placement: .saved, group: group)
        let middle = makeTab("Middle", placement: .saved, group: group)
        let tail = makeTab("Tail", placement: .saved, group: group)
        let current = makeTab("Current")
        let space = makeSpace(
            tabs: [head, middle, tail, current],
            selectedTabID: head.id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.removeTabFromSplit(middle.id, in: space.id, at: mutationDate)
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
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

    func testSteppingACardLeftAndRightSwapsItWithItsNeighbour() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let middle = makeTab("Middle", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, middle, tail], selectedTabID: head.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.moveSplitMember(middle.id, by: -1, in: space.id, at: mutationDate)
        )
        XCTAssertEqual(
            try XCTUnwrap(session.space(id: space.id)).splitGroupMembers(of: group)
                .map(\.id),
            [middle.id, head.id, tail.id]
        )

        XCTAssertTrue(
            session.moveSplitMember(middle.id, by: 1, in: space.id, at: mutationDate)
        )
        XCTAssertEqual(
            try XCTUnwrap(session.space(id: space.id)).splitGroupMembers(of: group)
                .map(\.id),
            [head.id, middle.id, tail.id],
            "Stepping back the other way restores the order it started in."
        )
    }

    func testSteppingPastEitherEndIsRefusedRatherThanWrapped() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail], selectedTabID: head.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertFalse(
            session.moveSplitMember(head.id, by: -1, in: space.id, at: mutationDate)
        )
        XCTAssertFalse(
            session.moveSplitMember(tail.id, by: 1, in: space.id, at: mutationDate)
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(repaired.tabs.map(\.id), [head.id, tail.id])
        XCTAssertNil(
            repaired.tabs[0].positionModifiedAt,
            "A refused move must not stamp a position nobody changed."
        )
        XCTAssertNil(repaired.tabs[1].positionModifiedAt)
    }

    func testAnOutOfRangeMemberIndexIsClampedIntoTheRun() throws {
        let group = SplitGroupID()
        let members = (0..<3).map { makeTab("Member \($0)", group: group) }
        let space = makeSpace(tabs: members, selectedTabID: members[0].id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.moveSplitMember(
                members[0].id,
                toMemberIndex: 99,
                in: space.id,
                at: mutationDate
            ),
            "A card drag reports the nearest gap, and the gap past the end is the end."
        )
        XCTAssertEqual(
            try XCTUnwrap(session.space(id: space.id)).splitGroupMembers(of: group)
                .map(\.id),
            [members[1].id, members[2].id, members[0].id]
        )

        XCTAssertTrue(
            session.moveSplitMember(
                members[0].id,
                toMemberIndex: -4,
                in: space.id,
                at: mutationDate
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(session.space(id: space.id)).splitGroupMembers(of: group)
                .map(\.id),
            [members[0].id, members[1].id, members[2].id]
        )
    }

    func testClampingToTheSlotACardAlreadyHoldsChangesNothing() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail], selectedTabID: head.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertFalse(
            session.moveSplitMember(
                head.id,
                toMemberIndex: -1,
                in: space.id,
                at: mutationDate
            )
        )
        XCTAssertNil(
            try XCTUnwrap(session.space(id: space.id)).tabs[0].positionModifiedAt
        )
    }

    func testMovingIsRefusedForNonMembersAndForSubRenderableRuns() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let plain = makeTab("Plain")
        let lone = makeTab("Lone", group: SplitGroupID())
        let space = makeSpace(
            tabs: [head, tail, plain, lone],
            selectedTabID: head.id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertFalse(
            session.moveSplitMember(plain.id, by: -1, in: space.id, at: mutationDate)
        )
        XCTAssertFalse(
            session.moveSplitMember(
                lone.id,
                by: -1,
                in: space.id,
                at: mutationDate
            ),
            "A run too short to draw presents as a plain tab, so it reorders nothing."
        )
        XCTAssertFalse(
            session.moveSplitMember(
                TabID(),
                by: 1,
                in: space.id,
                at: mutationDate
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(session.space(id: space.id)).tabs.map(\.id),
            [head.id, tail.id, plain.id, lone.id]
        )
    }

    func testMovingStampsOnlyTheCardsWhoseSlotChanged() throws {
        let group = SplitGroupID()
        let members = (0..<4).map { makeTab("Member \($0)", group: group) }
        let outsider = makeTab("Outsider")
        let space = makeSpace(
            tabs: members + [outsider],
            selectedTabID: members[0].id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.moveSplitMember(
                members[3].id,
                toMemberIndex: 1,
                in: space.id,
                at: mutationDate
            )
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(
            repaired.splitGroupMembers(of: group).map(\.id),
            [members[0].id, members[3].id, members[1].id, members[2].id]
        )
        XCTAssertNil(
            repaired.tabs.first { $0.id == members[0].id }?.positionModifiedAt,
            "The head kept slot 0, so it has no position opinion to upload."
        )
        for shifted in [members[3], members[1], members[2]] {
            XCTAssertEqual(
                repaired.tabs.first { $0.id == shifted.id }?.positionModifiedAt,
                mutationDate,
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
        let space = makeSpace(
            tabs: [before, head, tail, after],
            selectedTabID: tail.id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.moveSplitMember(tail.id, by: -1, in: space.id, at: mutationDate)
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
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
            repaired.selectedTabID,
            tail.id,
            "Reordering the cards does not change which one the chrome speaks for."
        )
    }

    @MainActor
    func testTheStoreMovesCardsAndAnswersWhetherAMoveIsAvailable() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let middle = makeTab("Middle", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(
            tabs: [head, middle, tail],
            selectedTabID: middle.id
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )

        XCTAssertTrue(store.canMoveSplitMember(head.id, by: 1, matching: assignment))
        XCTAssertFalse(store.canMoveSplitMember(head.id, by: -1, matching: assignment))
        XCTAssertFalse(store.canMoveSplitMember(tail.id, by: 1, matching: assignment))
        XCTAssertFalse(store.canMoveSplitMember(head.id, by: 0, matching: assignment))

        XCTAssertTrue(store.moveSplitMember(tail.id, by: -1, matching: assignment))
        XCTAssertEqual(
            store.selectedSpace?.splitGroupMembers(of: group).map(\.id),
            [head.id, tail.id, middle.id]
        )
        XCTAssertEqual(
            store.selectedSpace?.selectedTabID,
            middle.id,
            "Moving a card never takes focus off the card the person is reading."
        )

        XCTAssertTrue(
            store.moveSplitMember(middle.id, toMemberIndex: 0, matching: assignment)
        )
        XCTAssertEqual(
            store.selectedSpace?.splitGroupMembers(of: group).map(\.id),
            [middle.id, head.id, tail.id]
        )
    }

    @MainActor
    func testTheStoreRefusesToMoveACardInAnUnselectedSpace() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let selected = makeSpace(
            name: "Selected",
            tabs: [makeTab("Only")],
            selectedTabID: nil
        )
        let other = makeSpace(
            name: "Other",
            tabs: [head, tail],
            selectedTabID: head.id
        )
        let store = BrowserStore(
            session: BrowserSession(
                spaces: [selected, other],
                selectedSpaceID: selected.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: other)

        XCTAssertFalse(store.canMoveSplitMember(head.id, by: 1, matching: assignment))
        XCTAssertFalse(store.moveSplitMember(head.id, by: 1, matching: assignment))
        XCTAssertEqual(
            store.session.space(id: other.id)?.tabs.map(\.id),
            [head.id, tail.id]
        )
    }

    func testDissolvingSeparatesEveryMemberInPlace() throws {
        let group = SplitGroupID()
        let members = (0..<3).map { makeTab("Member \($0)", group: group) }
        let space = makeSpace(tabs: members, selectedTabID: members[1].id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(session.dissolveSplit(group, in: space.id, at: mutationDate))

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(repaired.tabs.map(\.id), members.map(\.id))
        XCTAssertTrue(repaired.tabs.allSatisfy { $0.splitGroupID == nil })
        XCTAssertTrue(repaired.tabs.allSatisfy { $0.positionModifiedAt == mutationDate })
        XCTAssertFalse(session.dissolveSplit(group, in: space.id, at: mutationDate))
    }

    func testClosingACardDownToOneMemberDissolvesTheGroupAndArchivesItUngrouped() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail], selectedTabID: head.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        session.closeTab(tail.id, at: mutationDate)

        let repaired = try XCTUnwrap(session.space(id: space.id))
        XCTAssertEqual(repaired.tabs.map(\.id), [head.id])
        XCTAssertNil(repaired.tabs[0].splitGroupID)
        XCTAssertEqual(repaired.tabs[0].positionModifiedAt, mutationDate)
        XCTAssertNil(
            repaired.archivedTabs.last?.tab.splitGroupID,
            "An archived tab leaves its split behind."
        )
    }

    func testClosingOneOfThreeKeepsTheRemainingGroup() throws {
        let group = SplitGroupID()
        let members = (0..<3).map { makeTab("Member \($0)", group: group) }
        let space = makeSpace(tabs: members, selectedTabID: members[0].id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        session.closeTab(members[1].id, at: mutationDate)

        let repaired = try XCTUnwrap(session.space(id: space.id))
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
        let space = makeSpace(tabs: [lone], selectedTabID: lone.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        session.repairRuntimeIntegrity()

        let repaired = try XCTUnwrap(session.spaces.first)
        XCTAssertEqual(repaired.tabs[0].splitGroupID, group)
        XCTAssertEqual(repaired.tabs[0].positionModifiedAt, mutationDate)
        XCTAssertTrue(repaired.liveSplitGroupIDs.isEmpty)
    }

    func testPresentedMembersFollowTheSelectedTab() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let outsider = makeTab("Outsider")
        let space = makeSpace(tabs: [head, tail, outsider], selectedTabID: head.id)

        XCTAssertEqual(
            space.presentedSplitMembers(for: head.id).map(\.id),
            [head.id, tail.id]
        )
        XCTAssertEqual(
            space.presentedSplitMembers(for: outsider.id).map(\.id),
            [outsider.id]
        )
        XCTAssertTrue(space.presentedSplitMembers(for: nil).isEmpty)
        XCTAssertEqual(space.liveSplitGroupIDs, [group])
        XCTAssertNil(space.splitGroup(containing: outsider.id))
    }

    func testMovingAGroupRelocatesItsMembersAsAnOrderedBlock() throws {
        let group = SplitGroupID()
        let saved = makeTab("Saved", placement: .saved)
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let trailing = makeTab("Trailing")
        let space = makeSpace(
            tabs: [saved, head, tail, trailing],
            selectedTabID: head.id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

        XCTAssertTrue(
            session.moveSplitGroup(
                group,
                to: .saved,
                before: nil,
                in: space.id,
                at: mutationDate
            )
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
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

    @MainActor
    func testTheStoreRefusesToJoinATabFromAnotherSpace() throws {
        let target = makeTab("Target")
        let selected = makeSpace(name: "Selected", tabs: [target], selectedTabID: target.id)
        let foreign = makeTab("Foreign")
        let other = makeSpace(name: "Other", tabs: [foreign], selectedTabID: foreign.id)
        let store = BrowserStore(
            session: BrowserSession(
                spaces: [selected, other],
                selectedSpaceID: selected.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
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

    @MainActor
    func testTheStoreJoinsRemovesAndDissolvesInsideTheSelectedSpace() throws {
        let target = makeTab("Target")
        let joiner = makeTab("Joiner")
        let extra = makeTab("Extra")
        let space = makeSpace(tabs: [target, joiner, extra], selectedTabID: target.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
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

    // MARK: - "Split With Next Tab" candidate resolution

    @MainActor
    func testTheNextJoinCandidateIsTheFollowingTabInTheSelectedTabsSection()
        throws
    {
        let first = makeTab("First")
        let second = makeTab("Second")
        let saved = makeTab("Saved", placement: .saved)
        let store = makeStore(
            tabs: [first, second, saved],
            selectedTabID: first.id
        )

        XCTAssertEqual(store.nextSplitJoinCandidate?.id, second.id)
    }

    @MainActor
    func testTheLastTabInASectionHasNoJoinCandidate() throws {
        let current = makeTab("Current")
        let saved = makeTab("Saved", placement: .saved)
        let store = makeStore(
            tabs: [current, saved],
            selectedTabID: current.id
        )

        XCTAssertNil(
            store.nextSplitJoinCandidate,
            "A tab in another section is not the next tab in this one."
        )
    }

    @MainActor
    func testAFiledTabsJoinCandidateStaysInsideItsOwnFolder() throws {
        let home = SavedFolder(title: "Home", symbol: "folder")
        let other = SavedFolder(title: "Other", symbol: "folder")
        let head = makeTab("Head", placement: .saved, folderID: home.id)
        let interloper = makeTab("Interloper", placement: .saved, folderID: other.id)
        let sibling = makeTab("Sibling", placement: .saved, folderID: home.id)
        let store = makeStore(
            folders: [home, other],
            tabs: [head, interloper, sibling],
            selectedTabID: head.id
        )

        XCTAssertEqual(store.nextSplitJoinCandidate?.id, sibling.id)
    }

    @MainActor
    func testJoinCandidateResolutionSkipsGroupedTabsAndStartPages() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let draft = BrowserTab.startPage(lastActivatedAt: Date(timeIntervalSince1970: 0))
        let free = makeTab("Free")
        let store = makeStore(
            tabs: [head, tail, draft, free],
            selectedTabID: head.id
        )

        XCTAssertEqual(
            store.nextSplitJoinCandidate?.id,
            free.id,
            "Existing members and uncommitted drafts are not candidates."
        )
    }

    @MainActor
    func testAFullGroupAndAPinnedOrDraftSelectionOfferNoCandidate() throws {
        let group = SplitGroupID()
        let members = (1...4).map { makeTab("Member \($0)", group: group) }
        let free = makeTab("Free")
        let full = makeStore(
            tabs: members + [free],
            selectedTabID: members[0].id
        )
        XCTAssertNil(full.nextSplitJoinCandidate)

        let pinned = makeTab("Pinned", placement: .pinned)
        let pinnedNeighbour = makeTab("Neighbour", placement: .pinned)
        let pinnedStore = makeStore(
            tabs: [pinned, pinnedNeighbour],
            selectedTabID: pinned.id
        )
        XCTAssertNil(pinnedStore.nextSplitJoinCandidate)

        let draft = BrowserTab.startPage(lastActivatedAt: Date(timeIntervalSince1970: 0))
        let follower = makeTab("Follower")
        let draftStore = makeStore(
            tabs: [draft, follower],
            selectedTabID: draft.id
        )
        XCTAssertNil(draftStore.nextSplitJoinCandidate)
    }

    // MARK: - "Split with Current Tab" and "Open Link in Split View"

    @MainActor
    func testSplittingWithTheCurrentTabJoinsTheSubjectAndFocusesIt() throws {
        let selected = makeTab("Selected")
        let subject = makeTab("Subject", placement: .pinned)
        let space = makeSpace(tabs: [selected, subject], selectedTabID: selected.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )

        XCTAssertTrue(
            store.canSplitTabWithSelectedTab(subject.id, matching: assignment),
            "A pinned subject is allowed: the placement plan moves it out of pinned."
        )
        XCTAssertTrue(
            store.splitTabWithSelectedTab(subject.id, matching: assignment)
        )

        let grouped = try XCTUnwrap(store.selectedSpace)
        let groupID = try XCTUnwrap(grouped.splitGroup(containing: selected.id))
        XCTAssertEqual(
            grouped.splitGroupMembers(of: groupID).map(\.id),
            [selected.id, subject.id]
        )
        XCTAssertEqual(
            grouped.tabs.first { $0.id == subject.id }?.placement,
            .current
        )
        XCTAssertEqual(grouped.selectedTabID, subject.id)
    }

    @MainActor
    func testSplittingWithTheCurrentTabIsRefusedForSelfSiblingsAndFullGroups()
        throws
    {
        let group = SplitGroupID()
        let members = (1...4).map { makeTab("Member \($0)", group: group) }
        let outsider = makeTab("Outsider")
        let space = makeSpace(
            tabs: members + [outsider],
            selectedTabID: members[0].id
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )

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

    @MainActor
    func testOpeningALinkInSplitViewCreatesTheTabAndGroupsItWithTheTarget()
        throws
    {
        let target = makeTab("Target")
        let space = makeSpace(tabs: [target], selectedTabID: target.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
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
        XCTAssertEqual(grouped.selectedTabID, openedID)
    }

    @MainActor
    func testTheWebContentMenuOffersSplitViewForACardWithRoomToGrow() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let lone = makeTab("Lone")
        let space = makeSpace(
            tabs: [head, tail, lone],
            selectedTabID: head.id
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )

        XCTAssertTrue(
            store.canOpenLinkInSplit(joining: tail.id, matching: assignment),
            "Every card of a two-member split can still take a third."
        )
        XCTAssertTrue(
            store.canOpenLinkInSplit(joining: lone.id, matching: assignment),
            "A lone tab creates the group."
        )
    }

    @MainActor
    func testTheWebContentMenuOmitsSplitViewForFullPinnedAndDraftCards() throws {
        let group = SplitGroupID()
        let members = (1...4).map { makeTab("Member \($0)", group: group) }
        let pinned = makeTab("Pinned", placement: .pinned)
        let draft = BrowserTab.startPage(
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        )
        let space = makeSpace(
            tabs: members + [pinned, draft],
            selectedTabID: members[0].id
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )

        XCTAssertFalse(
            store.canOpenLinkInSplit(joining: members[0].id, matching: assignment),
            "A group at capacity takes no more cards."
        )
        XCTAssertFalse(
            store.canOpenLinkInSplit(joining: pinned.id, matching: assignment),
            "Pinned tabs never take part in a split."
        )
        XCTAssertFalse(
            store.canOpenLinkInSplit(joining: draft.id, matching: assignment),
            "A Start Page is a draft the sidebar does not even list."
        )
        XCTAssertFalse(
            store.canOpenLinkInSplit(
                joining: members[0].id,
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: SpaceID(),
                    profileID: assignment.profileID
                )
            ),
            "A split never spans Spaces."
        )
    }

    func testSplitGroupCustomizationPersistsEveryFieldAndFullEmojiCluster()
        throws
    {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail], selectedTabID: head.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let tint = BrowserSpaceBrandColor(red: 0.16, green: 0.48, blue: 0.82)
        let emoji = "👨🏽‍💻"

        XCTAssertTrue(
            session.setSplitGroupTitle(
                "  Research Pair  ",
                groupID: group,
                in: space.id,
                at: mutationDate
            )
        )
        XCTAssertTrue(
            session.setSplitGroupEmojiIcon(
                emoji,
                groupID: group,
                in: space.id,
                at: mutationDate.addingTimeInterval(1)
            )
        )
        XCTAssertTrue(
            session.setSplitGroupTint(
                tint,
                groupID: group,
                in: space.id,
                at: mutationDate.addingTimeInterval(2)
            )
        )

        let decoded = try JSONDecoder().decode(
            BrowserSession.self,
            from: JSONEncoder().encode(session)
        )
        let metadata = try XCTUnwrap(
            decoded.space(id: space.id)?.splitGroupMetadata(for: group)
        )
        XCTAssertEqual(metadata.displayTitle, "Research Pair")
        XCTAssertEqual(metadata.emojiIcon, emoji)
        XCTAssertEqual(metadata.tint, tint)
        XCTAssertEqual(metadata.titleModifiedAt, mutationDate)
        XCTAssertEqual(
            metadata.iconModifiedAt,
            mutationDate.addingTimeInterval(1)
        )
        XCTAssertEqual(
            metadata.tintModifiedAt,
            mutationDate.addingTimeInterval(2)
        )
    }

    func testDissolvingAGroupRemovesItsDurableCustomization() throws {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail], selectedTabID: head.id)
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        XCTAssertTrue(
            session.setSplitGroupTitle(
                "Temporary Pair",
                groupID: group,
                in: space.id,
                at: mutationDate
            )
        )

        XCTAssertTrue(
            session.removeTabFromSplit(
                tail.id,
                in: space.id,
                at: mutationDate.addingTimeInterval(1)
            )
        )

        let repaired = try XCTUnwrap(session.space(id: space.id))
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
            splitGroups: [metadata],
            selectedTabID: lone.id
        )

        let session = BrowserSession(spaces: [space], selectedSpaceID: space.id)

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
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
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

    @MainActor
    private func makeStore(
        folders: [SavedFolder] = [],
        tabs: [BrowserTab],
        selectedTabID: TabID?
    ) -> BrowserStore {
        let space = makeSpace(
            folders: folders,
            tabs: tabs,
            selectedTabID: selectedTabID
        )
        return BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
    }

    private func makeSpace(
        name: String = "Work",
        folders: [SavedFolder] = [],
        tabs: [BrowserTab],
        selectedTabID: TabID?
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: folders,
            tabs: tabs,
            selectedTabID: selectedTabID
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
