import Foundation
import XCTest

@testable import Crest

final class BrowserSplitGroupNormalizerTests: XCTestCase {
    func testPinnedMembersLoseTheirGroup() {
        let group = SplitGroupID()
        let pinned = makeTab("Pinned", placement: .pinned, group: group)
        let current = makeTab("Current", group: group)

        let normalized = BrowserSplitGroupNormalizer.normalized([pinned, current])

        XCTAssertNil(normalized[0].splitGroupID)
        XCTAssertEqual(
            normalized[1].splitGroupID,
            group,
            "Clearing the pinned member must not punish the non-pinned one."
        )
    }

    func testAnInterruptedRunKeepsOnlyItsFirstSegment() {
        let group = SplitGroupID()
        let first = makeTab("First", group: group)
        let second = makeTab("Second", group: group)
        let outsider = makeTab("Outsider")
        let third = makeTab("Third", group: group)

        let normalized = BrowserSplitGroupNormalizer.normalized([
            first, second, outsider, third,
        ])

        XCTAssertEqual(normalized[0].splitGroupID, group)
        XCTAssertEqual(normalized[1].splitGroupID, group)
        XCTAssertNil(normalized[2].splitGroupID)
        XCTAssertNil(
            normalized[3].splitGroupID,
            "A later re-occurrence of an ID is not part of that group's run."
        )
    }

    func testADuplicateRunLaterInTheArrayIsClearedEntirely() {
        let group = SplitGroupID()
        let firstRun = [makeTab("A", group: group), makeTab("B", group: group)]
        let gap = makeTab("Gap")
        let secondRun = [makeTab("C", group: group), makeTab("D", group: group)]

        let normalized = BrowserSplitGroupNormalizer.normalized(firstRun + [gap] + secondRun)

        XCTAssertEqual(normalized.compactMap(\.splitGroupID), [group, group])
        XCTAssertNil(normalized[3].splitGroupID)
        XCTAssertNil(normalized[4].splitGroupID)
    }

    func testAPlacementMismatchSplitsTheRunAtThatMember() {
        let group = SplitGroupID()
        let head = makeTab("Head", placement: .saved, group: group)
        let stranger = makeTab("Stranger", placement: .current, group: group)
        let trailing = makeTab("Trailing", placement: .saved, group: group)

        let normalized = BrowserSplitGroupNormalizer.normalized([head, stranger, trailing])

        XCTAssertEqual(normalized[0].splitGroupID, group)
        XCTAssertNil(normalized[1].splitGroupID)
        XCTAssertNil(normalized[2].splitGroupID)
    }

    func testAFolderMismatchSplitsTheRunAtThatMember() {
        let group = SplitGroupID()
        let folderID = FolderID()
        let head = makeTab("Head", placement: .saved, folderID: folderID, group: group)
        let sibling = makeTab("Sibling", placement: .saved, folderID: folderID, group: group)
        let unfiled = makeTab("Unfiled", placement: .saved, group: group)

        let normalized = BrowserSplitGroupNormalizer.normalized([head, sibling, unfiled])

        XCTAssertEqual(normalized[0].splitGroupID, group)
        XCTAssertEqual(normalized[1].splitGroupID, group)
        XCTAssertNil(normalized[2].splitGroupID)
    }

    func testTheCapKeepsTheFirstFourMembersAndTrimsTheRest() {
        let group = SplitGroupID()
        let members = (0..<6).map { makeTab("Member \($0)", group: group) }

        let normalized = BrowserSplitGroupNormalizer.normalized(members)

        XCTAssertEqual(
            normalized.prefix(BrowserSplitGroupPolicy.maximumMembers).compactMap(\.splitGroupID),
            Array(repeating: group, count: BrowserSplitGroupPolicy.maximumMembers)
        )
        XCTAssertNil(normalized[4].splitGroupID)
        XCTAssertNil(normalized[5].splitGroupID)
    }

    func testALoneMemberKeepsItsGroup() {
        let group = SplitGroupID()
        let lone = makeTab("Lone", group: group)
        let neighbour = makeTab("Neighbour")

        let normalized = BrowserSplitGroupNormalizer.normalized([lone, neighbour])

        XCTAssertEqual(
            normalized[0].splitGroupID,
            group,
            """
            Repair must never dissolve a singleton: a device that materializes \
            1-of-3 synced members first would otherwise strip the membership and \
            re-upload the strip to every other device.
            """
        )
    }

    func testNormalizationIsIdempotent() {
        let first = SplitGroupID()
        let second = SplitGroupID()
        let folderID = FolderID()
        let tabs = [
            makeTab("Pinned", placement: .pinned, group: first),
            makeTab("Head", group: first),
            makeTab("Member", group: first),
            makeTab("Mismatch", placement: .saved, folderID: folderID, group: first),
            makeTab("Duplicate", group: first),
            makeTab("Second head", group: second),
            makeTab("Second member", group: second),
            makeTab("Second overflow A", group: second),
            makeTab("Second overflow B", group: second),
            makeTab("Second overflow C", group: second),
            makeTab("Plain"),
        ]

        let once = BrowserSplitGroupNormalizer.normalized(tabs)
        let twice = BrowserSplitGroupNormalizer.normalized(once)

        XCTAssertEqual(once, twice)
    }

    func testNormalizationNeitherReordersTabsNorTouchesPositionTimestamps() {
        let group = SplitGroupID()
        let stamp = Date(timeIntervalSince1970: 1_000)
        var pinned = makeTab("Pinned", placement: .pinned, group: group)
        pinned.markPositionModified(at: stamp)
        var current = makeTab("Current", group: group)
        current.markPositionModified(at: stamp)

        let normalized = BrowserSplitGroupNormalizer.normalized([current, pinned])

        XCTAssertEqual(normalized.map(\.id), [current.id, pinned.id])
        XCTAssertEqual(normalized[0].positionModifiedAt, stamp)
        XCTAssertEqual(
            normalized[1].positionModifiedAt,
            stamp,
            "Clearing membership during repair must not look like a user move to sync."
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
