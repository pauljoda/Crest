import Foundation
import XCTest

@testable import Crest

final class BrowserSidebarTabListItemPolicyTests: XCTestCase {
    func testAContiguousRunFoldsIntoOneGroupRow() {
        let group = SplitGroupID(rawValue: Self.uuid(0x01))
        let first = makeTab(0x11, "First", group: group)
        let second = makeTab(0x12, "Second", group: group)
        let third = makeTab(0x13, "Third", group: group)

        let items = BrowserSidebarTabListItemPolicy.items(
            for: [first, second, third]
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(
            items,
            [.splitGroup(id: group, members: [first, second, third])]
        )
        XCTAssertEqual(items.map(\.id), [.splitGroup(group)])
    }

    /// Storage keeps a lone member's ID so a staggered sync can reconstitute the
    /// group; the sidebar must still draw it as an ordinary tab.
    func testASingletonMemberStaysAPlainTab() {
        let group = SplitGroupID(rawValue: Self.uuid(0x02))
        let lone = makeTab(0x21, "Lone", group: group)
        let plain = makeTab(0x22, "Plain")

        let items = BrowserSidebarTabListItemPolicy.items(for: [lone, plain])

        XCTAssertEqual(items, [.tab(lone), .tab(plain)])
        XCTAssertEqual(items.map(\.id), [.tab(lone.id), .tab(plain.id)])
    }

    func testRowOrderAndMembershipFollowTheSessionArray() {
        let group = SplitGroupID(rawValue: Self.uuid(0x03))
        let leading = makeTab(0x31, "Leading")
        let head = makeTab(0x32, "Head", group: group)
        let tail = makeTab(0x33, "Tail", group: group)
        let trailing = makeTab(0x34, "Trailing")

        let items = BrowserSidebarTabListItemPolicy.items(
            for: [leading, head, tail, trailing]
        )

        XCTAssertEqual(
            items,
            [
                .tab(leading),
                .splitGroup(id: group, members: [head, tail]),
                .tab(trailing),
            ]
        )
        XCTAssertEqual(
            items.flatMap(\.tabs).map(\.id),
            [leading.id, head.id, tail.id, trailing.id],
            "Folding must preserve every tab and its order."
        )
    }

    /// Two groups in a row stay two rows rather than merging into one.
    func testAdjacentGroupsFoldSeparately() {
        let first = SplitGroupID(rawValue: Self.uuid(0x04))
        let second = SplitGroupID(rawValue: Self.uuid(0x05))
        let tabs = [
            makeTab(0x41, "A", group: first),
            makeTab(0x42, "B", group: first),
            makeTab(0x43, "C", group: second),
            makeTab(0x44, "D", group: second),
        ]

        let items = BrowserSidebarTabListItemPolicy.items(for: tabs)

        XCTAssertEqual(
            items.map(\.id),
            [.splitGroup(first), .splitGroup(second)]
        )
    }

    /// Defensive: the normalizer clears a second occurrence of a group ID, so a
    /// list carrying one is malformed. It must never produce two rows claiming
    /// the same identity — `ForEach` would then have duplicate IDs.
    func testARepeatedGroupIDNeverProducesASecondGroupRow() {
        let group = SplitGroupID(rawValue: Self.uuid(0x06))
        let head = makeTab(0x51, "Head", group: group)
        let tail = makeTab(0x52, "Tail", group: group)
        let interloper = makeTab(0x53, "Interloper")
        let strayHead = makeTab(0x54, "Stray Head", group: group)
        let strayTail = makeTab(0x55, "Stray Tail", group: group)

        let items = BrowserSidebarTabListItemPolicy.items(
            for: [head, tail, interloper, strayHead, strayTail]
        )

        XCTAssertEqual(
            items,
            [
                .splitGroup(id: group, members: [head, tail]),
                .tab(interloper),
                .tab(strayHead),
                .tab(strayTail),
            ]
        )
        XCTAssertEqual(
            Set(items.map(\.id)).count,
            items.count,
            "Row identities must be unique."
        )
    }

    /// Defensive: an interleaved list has no run long enough to render, so every
    /// tab stays a plain row.
    func testAnInterleavedRunRendersAsPlainTabs() {
        let group = SplitGroupID(rawValue: Self.uuid(0x07))
        let tabs = [
            makeTab(0x61, "A", group: group),
            makeTab(0x62, "B"),
            makeTab(0x63, "C", group: group),
        ]

        let items = BrowserSidebarTabListItemPolicy.items(for: tabs)

        XCTAssertEqual(items, tabs.map { .tab($0) })
    }

    /// Pinned tabs are a grid of shortcuts rather than an ordered run, so they
    /// never fold even if a stale membership rode in on them.
    func testPinnedTabsNeverFold() {
        let group = SplitGroupID(rawValue: Self.uuid(0x08))
        let tabs = [
            makeTab(0x71, "A", group: group, placement: .pinned),
            makeTab(0x72, "B", group: group, placement: .pinned),
        ]

        let items = BrowserSidebarTabListItemPolicy.items(for: tabs)

        XCTAssertEqual(items, tabs.map { .tab($0) })
    }

    /// A pinned member cannot join a run around it either: it breaks contiguity
    /// rather than being folded in.
    func testAPinnedTabBreaksTheRunAroundIt() {
        let group = SplitGroupID(rawValue: Self.uuid(0x09))
        let head = makeTab(0x81, "Head", group: group)
        let pinned = makeTab(0x82, "Pinned", group: group, placement: .pinned)
        let tail = makeTab(0x83, "Tail", group: group)

        let items = BrowserSidebarTabListItemPolicy.items(
            for: [head, pinned, tail]
        )

        XCTAssertEqual(items, [.tab(head), .tab(pinned), .tab(tail)])
    }

    /// The row identity is the group's, not its members', so the row survives a
    /// member arriving or leaving instead of being rebuilt.
    func testGroupRowIdentityIsStableAcrossMembershipChanges() {
        let group = SplitGroupID(rawValue: Self.uuid(0x0A))
        let head = makeTab(0x91, "Head", group: group)
        let tail = makeTab(0x92, "Tail", group: group)
        let joiner = makeTab(0x93, "Joiner", group: group)

        let before = BrowserSidebarTabListItemPolicy.items(for: [head, tail])
        let after = BrowserSidebarTabListItemPolicy.items(
            for: [head, tail, joiner]
        )

        XCTAssertEqual(before.map(\.id), after.map(\.id))
        XCTAssertEqual(
            before.map(\.collectionMotionID),
            after.map(\.collectionMotionID)
        )
        XCTAssertNotEqual(before, after)
    }

    func testCollectionMotionIdentitiesDistinguishGroupsFromTabs() {
        let group = SplitGroupID(rawValue: Self.uuid(0x0B))
        let head = makeTab(0xA1, "Head", group: group)
        let tail = makeTab(0xA2, "Tail", group: group)

        let grouped = BrowserSidebarTabListItemPolicy.items(for: [head, tail])
        let ungrouped = BrowserSidebarTabListItemPolicy.items(
            for: [head, tail].map { tab in
                var plain = tab
                plain.splitGroupID = nil
                return plain
            }
        )

        XCTAssertEqual(
            grouped.map(\.collectionMotionID),
            ["split-\(group.rawValue.uuidString)"]
        )
        XCTAssertEqual(
            ungrouped.map(\.collectionMotionID),
            [
                "tab-\(head.id.rawValue.uuidString)",
                "tab-\(tail.id.rawValue.uuidString)",
            ]
        )
    }

    /// A group is one row, so the anchor a drop below it resolves to is the tab
    /// following its *last* member. Both platforms compose the item policy with
    /// `followingTabIDs` exactly this way; an anchor landing inside the run is
    /// what would drop a foreign tab between two members and split the group.
    func testAGroupRowsTrailingDropAnchorSkipsPastEveryMember() {
        let group = SplitGroupID(rawValue: Self.uuid(0x0C))
        let leading = makeTab(0xB1, "Leading")
        let head = makeTab(0xB2, "Head", group: group)
        let middle = makeTab(0xB3, "Middle", group: group)
        let tail = makeTab(0xB4, "Tail", group: group)
        let trailing = makeTab(0xB5, "Trailing")
        let tabs = [leading, head, middle, tail, trailing]

        let items = BrowserSidebarTabListItemPolicy.items(for: tabs)
        let followingTabIDs = BrowserTabRowInsertionPolicy.followingTabIDs(
            in: tabs
        )

        XCTAssertEqual(
            items.map(\.id),
            [.tab(leading.id), .splitGroup(group), .tab(trailing.id)]
        )
        XCTAssertEqual(
            followingTabIDs[leading.id],
            head.id,
            "The row above a group anchors on the group's first member."
        )
        XCTAssertEqual(
            items[1].tabs.last.flatMap { followingTabIDs[$0.id] },
            trailing.id,
            "The row below a group anchors past its last member."
        )
    }

    /// A group closing a section has no following row, so its own trailing
    /// indicator is the only one drawn there — the same ownership rule an
    /// ordinary last row follows.
    func testAGroupClosingASectionHasNoFollowingRow() {
        let group = SplitGroupID(rawValue: Self.uuid(0x0D))
        let head = makeTab(0xC1, "Head", group: group)
        let tail = makeTab(0xC2, "Tail", group: group)
        let tabs = [head, tail]

        let items = BrowserSidebarTabListItemPolicy.items(for: tabs)
        let followingTabIDs = BrowserTabRowInsertionPolicy.followingTabIDs(
            in: tabs
        )
        let followingTabID = items[0].tabs.last.flatMap {
            followingTabIDs[$0.id]
        }

        XCTAssertNil(followingTabID)
        XCTAssertTrue(
            BrowserTabRowIndicatorOwnershipPolicy.showsAfterRowIndicator(
                hasVisibleFollowingRow: followingTabID != nil
            )
        )
    }

    func testCollapsedFolderKeepsTheWholeSelectedSplitGroupVisible() throws {
        let group = SplitGroupID(rawValue: Self.uuid(0x0E))
        let head = makeTab(0xD1, "Head", group: group, placement: .saved)
        let selected = makeTab(
            0xD2,
            "Selected",
            group: group,
            placement: .saved
        )
        let neighbor = makeTab(0xD3, "Neighbor", placement: .saved)

        let item = try XCTUnwrap(
            BrowserSidebarTabListItemPolicy.collapsedItem(
                keeping: selected.id,
                in: [head, selected, neighbor]
            )
        )

        XCTAssertEqual(
            item,
            .splitGroup(id: group, members: [head, selected]),
            "The collapsed representation must match the split still presented in content."
        )
    }

    func testCollapsedFolderKeepsAnOrdinarySelectedTabAsAPlainRow() throws {
        let selected = makeTab(0xE1, "Selected", placement: .saved)
        let neighbor = makeTab(0xE2, "Neighbor", placement: .saved)

        XCTAssertEqual(
            BrowserSidebarTabListItemPolicy.collapsedItem(
                keeping: selected.id,
                in: [selected, neighbor]
            ),
            .tab(selected)
        )
        XCTAssertNil(
            BrowserSidebarTabListItemPolicy.collapsedItem(
                keeping: TabID(),
                in: [selected, neighbor]
            ),
            "A collapsed, nonselected folder does not invent a retained row."
        )
    }

    func testAnEmptySectionHasNoRows() {
        XCTAssertTrue(BrowserSidebarTabListItemPolicy.items(for: []).isEmpty)
    }

    private func makeTab(
        _ finalByte: UInt8,
        _ title: String,
        group: SplitGroupID? = nil,
        placement: TabPlacement = .current
    ) -> BrowserTab {
        BrowserTab(
            id: TabID(rawValue: Self.uuid(finalByte)),
            title: title,
            url: URL(fileURLWithPath: "/crest-sidebar-item-policy/\(title)"),
            placement: placement,
            splitGroupID: group,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x49,
                0x54, 0x45, 0x4D, 0x53, 0x00, 0x00, 0x00, finalByte
            )
        )
    }
}
