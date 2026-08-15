import CoreGraphics
import Foundation
import XCTest

@testable import Crest

/// Drag-to-split: where a tab dropped on the content area lands, and when the
/// content area refuses it outright.
@MainActor
final class BrowserSplitDropPolicyTests: XCTestCase {

    // MARK: - Insertion index

    /// Cards are passed once the pointer is beyond their midpoint, exactly as
    /// list rows are.
    func testInsertionIndexCountsTheCardsThePointerHasPassed() {
        let cards = Self.cardFrames(count: 3)

        XCTAssertEqual(Self.index(atX: 10, in: cards), 0)
        XCTAssertEqual(Self.index(atX: 149, in: cards), 0)
        XCTAssertEqual(Self.index(atX: 151, in: cards), 1)
        XCTAssertEqual(Self.index(atX: 457, in: cards), 1)
        XCTAssertEqual(Self.index(atX: 459, in: cards), 2)
        XCTAssertEqual(Self.index(atX: 767, in: cards), 3)
        XCTAssertEqual(
            Self.index(atX: 5_000, in: cards),
            3,
            "Overshooting the row appends rather than resolving nothing."
        )
    }

    /// The midpoint itself is not past the card: the comparison is strict, so a
    /// pointer resting exactly on the seam keeps the lower slot.
    func testACardsMidpointIsNotPastIt() {
        let cards = Self.cardFrames(count: 2)

        XCTAssertEqual(Self.index(atX: 150, in: cards), 0)
        XCTAssertEqual(Self.index(atX: 458, in: cards), 1)
    }

    /// The lone-tab case, which is how a split gets created at all.
    func testASingleCardSplitsIntoALeadingAndATrailingHalf() {
        let card = [CGRect(x: 0, y: 0, width: 900, height: 600)]

        XCTAssertEqual(Self.index(atX: 100, in: card), 0)
        XCTAssertEqual(Self.index(atX: 800, in: card), 1)
    }

    func testNoCardsResolveToTheFirstSlot() {
        XCTAssertEqual(Self.index(atX: 400, in: []), 0)
    }

    /// Ordering comes from the leading edges, and a hidden duplicate of a live
    /// card — an empty frame — is not a card at all.
    func testOrderingSortsByLeadingEdgeAndDropsEmptyFrames() {
        let leading = CGRect(x: 0, y: 0, width: 300, height: 600)
        let trailing = CGRect(x: 308, y: 0, width: 300, height: 600)
        let hidden = CGRect(x: 120, y: 0, width: 0, height: 0)

        XCTAssertEqual(
            BrowserSplitDropPolicy.ordered([trailing, hidden, leading]),
            [leading, trailing]
        )
    }

    /// The placeholder the drop opens moves every card, and the index has to
    /// survive that or the target would flicker between two slots under a
    /// stationary pointer. Earlier cards shrink toward the leading edge and
    /// later ones are pushed away, both of which reinforce the answer.
    func testTheIndexSurvivesTheLayoutItsOwnPlaceholderCauses() {
        let containerWidth: CGFloat = 900
        let fractions = [0.5, 0.5]
        let widths = BrowserSplitColumnLayout.widths(
            containerWidth: containerWidth,
            fractions: fractions
        )

        for pointerX in stride(from: CGFloat(5), to: containerWidth, by: 5) {
            let restingCards = Self.frames(widths: widths)
            let index = BrowserSplitDropPolicy.insertionIndex(
                at: CGPoint(x: pointerX, y: 300),
                orderedCardFrames: restingCards
            )
            // The drop column is a column: every slot, cards included, is
            // re-shared for the split the drop would make.
            let dragging = BrowserSplitColumnLayout.widths(
                containerWidth: containerWidth,
                fractions: BrowserSplitColumnLayout.fractionsInserting(
                    at: index,
                    into: fractions
                )
            )
            var shifted = dragging
            let placeholderWidth = shifted.remove(at: index)
            let shiftedCards = Self.frames(
                widths: shifted,
                placeholderWidth: placeholderWidth,
                placeholderIndex: index
            )

            XCTAssertEqual(
                BrowserSplitDropPolicy.insertionIndex(
                    at: CGPoint(x: pointerX, y: 300),
                    orderedCardFrames: shiftedCards
                ),
                index,
                "A pointer at \(pointerX) changed slot once the placeholder opened."
            )
        }
    }

    // MARK: - Acceptance: what the zone itself refuses

    /// Only a tab becomes a card. A folder has no page, and a whole group would
    /// have to mean "present these instead", which is not a defined gesture.
    func testTheContentZoneTakesTabsOnly() {
        let assignment = Self.assignment
        let zones = [
            BrowserSidebarReorderZone(
                target: .splitContent(assignment),
                frame: Self.contentFrame
            )
        ]
        let point = CGPoint(x: 400, y: 300)

        XCTAssertEqual(
            BrowserSidebarReorderPolicy.zone(
                at: point,
                in: zones,
                accepting: Self.tabItem(in: assignment)
            )?
            .target,
            .splitContent(assignment)
        )
        XCTAssertNil(
            BrowserSidebarReorderPolicy.zone(
                at: point,
                in: zones,
                accepting: Self.folderItem(in: assignment)
            )
        )
        XCTAssertNil(
            BrowserSidebarReorderPolicy.zone(
                at: point,
                in: zones,
                accepting: Self.groupItem(in: assignment)
            )
        )
    }

    /// A split never spans Spaces, so a tab from another one is refused where it
    /// would otherwise be silently relocated first.
    func testTheContentZoneRefusesATabFromAnotherSpace() {
        let zones = [
            BrowserSidebarReorderZone(
                target: .splitContent(Self.assignment),
                frame: Self.contentFrame
            )
        ]

        XCTAssertNil(
            BrowserSidebarReorderPolicy.zone(
                at: CGPoint(x: 400, y: 300),
                in: zones,
                accepting: Self.tabItem(
                    in: BrowserSpaceRuntimeAssignment(
                        spaceID: SpaceID(),
                        profileID: UUID()
                    )
                )
            )
        )
    }

    /// The content area is the least specific zone in the window: a sidebar
    /// floating over it keeps every drop that lands on a list.
    func testAnOverlappingSectionOutranksTheContentArea() {
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let zones = [
            BrowserSidebarReorderZone(
                target: .splitContent(Self.assignment),
                frame: Self.contentFrame
            ),
            BrowserSidebarReorderZone(
                target: .section(section),
                frame: CGRect(x: 0, y: 0, width: 260, height: 600)
            ),
        ]

        XCTAssertEqual(
            BrowserSidebarReorderPolicy.zone(
                at: CGPoint(x: 120, y: 300),
                in: zones,
                accepting: Self.tabItem(in: Self.assignment)
            )?
            .target,
            .section(section)
        )
        XCTAssertEqual(
            BrowserSidebarReorderPolicy.zone(
                at: CGPoint(x: 600, y: 300),
                in: zones,
                accepting: Self.tabItem(in: Self.assignment)
            )?
            .target,
            .splitContent(Self.assignment),
            "Past the sidebar there is nothing else to outrank it."
        )
    }

    // MARK: - Acceptance: what the presented cards refuse

    /// A resolved target and the slot it names, from cards the state measured.
    func testResolutionOverRegisteredCardsNamesTheSlotUnderThePointer() {
        let state = Self.stateWithCards(count: 2)

        state.begin(
            item: Self.tabItem(in: Self.assignment),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 20)
        )
        state.update(pointer: CGPoint(x: 600, y: 300))

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .splitInsert(assignment: Self.assignment, index: 1)
        )
        XCTAssertEqual(state.liftTargetShape, .webpageCard)
        XCTAssertTrue(state.hasEnteredSplitContent)
        state.cancel()
    }

    /// A tab already on show has nothing to join. That covers the lone tab in an
    /// unsplit window dropped onto itself as much as a member of a live split.
    func testAPresentedTabIsRefusedByItsOwnContentArea() {
        let presented = TabID()
        let state = Self.stateWithCards(count: 2, firstTabID: presented)

        state.begin(
            item: Self.tabItem(in: Self.assignment, tabID: presented),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 20)
        )
        state.update(pointer: CGPoint(x: 460, y: 300))

        XCTAssertNil(state.resolvedTarget)
        XCTAssertEqual(
            state.liftTargetShape,
            .row,
            "An unresolved drag holds the shape it started as."
        )
        XCTAssertFalse(state.hasEnteredSplitContent)
        state.cancel()
    }

    /// A full group shows no insertion point, because the model would refuse the
    /// join and the placeholder would be a promise nobody keeps.
    func testAFullGroupOffersNoInsertionPoint() {
        let state = Self.stateWithCards(
            count: BrowserSplitGroupPolicy.maximumMembers
        )

        state.begin(
            item: Self.tabItem(in: Self.assignment),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 20)
        )
        state.update(pointer: CGPoint(x: 460, y: 300))

        XCTAssertNil(state.resolvedTarget)
        state.cancel()
    }

    /// Nothing presented — a locked Space, a window with no selection — is not a
    /// place to drop a card either.
    func testAnEmptyContentAreaOffersNoInsertionPoint() {
        let state = Self.stateWithCards(count: 0)

        state.begin(
            item: Self.tabItem(in: Self.assignment),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 20)
        )
        state.update(pointer: CGPoint(x: 460, y: 300))

        XCTAssertNil(state.resolvedTarget)
        state.cancel()
    }

    /// Windows share one reorder state. A second window's cards must not be
    /// counted into the drop the pointer is making in this one, or the index
    /// would be off and a two-card split would report itself full.
    func testASecondWindowsCardsAreNotCountedIntoThisDrop() {
        let state = Self.stateWithCards(count: 2)
        // A second window to the left of this one, presenting the same Space
        // with the same two cards.
        for index in 0..<2 {
            state.register(
                splitCardFrame: CGRect(
                    x: -1_200 + CGFloat(index) * 500,
                    y: 0,
                    width: 446,
                    height: 600
                ),
                for: TabID(),
                owner: UUID()
            )
        }

        state.begin(
            item: Self.tabItem(in: Self.assignment),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 20)
        )
        state.update(pointer: CGPoint(x: 600, y: 300))

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .splitInsert(assignment: Self.assignment, index: 1),
            "The other window's two cards would have pushed this to index 3."
        )
        state.cancel()
    }

    /// A card that unregisters as the layout swaps hosts must not take the
    /// replacement's registration with it.
    func testAStaleCardRemovalCannotClearItsReplacement() {
        let state = BrowserSidebarReorderState()
        let tabID = TabID()
        let departing = UUID()
        let arriving = UUID()
        let frame = CGRect(x: 0, y: 0, width: 900, height: 600)

        state.register(splitCardFrame: frame, for: tabID, owner: departing)
        state.register(splitCardFrame: frame, for: tabID, owner: arriving)
        state.removeSplitCardFrame(for: tabID, owner: departing)

        XCTAssertEqual(state.orderedSplitCardFrames, [frame])

        state.removeSplitCardFrame(for: tabID, owner: arriving)
        XCTAssertTrue(state.orderedSplitCardFrames.isEmpty)
    }

    /// Entering the content area is a one-way door for the length of the drag:
    /// the columns layout it opens must not close again when the pointer leaves,
    /// or the live web view changes hosts twice per hover.
    func testTheContentAreaStaysEnteredForTheRestOfTheDrag() {
        let state = Self.stateWithCards(count: 1)

        state.begin(
            item: Self.tabItem(in: Self.assignment),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 20)
        )
        state.update(pointer: CGPoint(x: 460, y: 300))
        XCTAssertTrue(state.hasEnteredSplitContent)

        // Back over the sidebar: the placeholder goes, the layout stays.
        state.update(pointer: CGPoint(x: 100, y: 20))
        XCTAssertNil(state.resolvedTarget)
        XCTAssertTrue(state.hasEnteredSplitContent)

        state.cancel()
        XCTAssertFalse(state.hasEnteredSplitContent)
    }

    // MARK: - Fixtures

    private static let assignment = BrowserSpaceRuntimeAssignment(
        spaceID: SpaceID(rawValue: uuid(1)),
        profileID: uuid(2)
    )

    private static let contentFrame = CGRect(
        x: 260,
        y: 0,
        width: 900,
        height: 600
    )

    /// Three 300pt cards with an 8pt gap: midpoints at 150, 458, and 766.
    private static func cardFrames(count: Int) -> [CGRect] {
        frames(widths: Array(repeating: 300, count: count))
    }

    private static func frames(
        widths: [CGFloat],
        placeholderWidth: CGFloat? = nil,
        placeholderIndex: Int? = nil
    ) -> [CGRect] {
        let gap = BrowserSplitLayoutMetrics.interCardGap
        var origin: CGFloat = 0
        var frames: [CGRect] = []
        for (index, width) in widths.enumerated() {
            if index == placeholderIndex, let placeholderWidth {
                origin += placeholderWidth + gap
            }
            frames.append(CGRect(x: origin, y: 0, width: width, height: 600))
            origin += width + gap
        }
        return frames
    }

    private static func index(atX x: CGFloat, in frames: [CGRect]) -> Int {
        BrowserSplitDropPolicy.insertionIndex(
            at: CGPoint(x: x, y: 300),
            orderedCardFrames: frames
        )
    }

    /// A state whose content zone spans `contentFrame` and holds `count` cards
    /// of equal width inside it.
    private static func stateWithCards(
        count: Int,
        firstTabID: TabID? = nil
    ) -> BrowserSidebarReorderState {
        let state = BrowserSidebarReorderState()
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .splitContent(assignment),
                frame: contentFrame
            ),
            for: UUID()
        )
        guard count > 0 else { return state }

        let gap = BrowserSplitLayoutMetrics.interCardGap
        let width =
            (contentFrame.width - gap * CGFloat(count - 1)) / CGFloat(count)
        for index in 0..<count {
            state.register(
                splitCardFrame: CGRect(
                    x: contentFrame.minX + (width + gap) * CGFloat(index),
                    y: contentFrame.minY,
                    width: width,
                    height: contentFrame.height
                ),
                for: index == 0 ? (firstTabID ?? TabID()) : TabID(),
                owner: UUID()
            )
        }
        return state
    }

    private static func tabItem(
        in assignment: BrowserSpaceRuntimeAssignment,
        tabID: TabID = TabID()
    ) -> BrowserSidebarReorderItem {
        .tab(
            BrowserTabDragItem(
                tabID: tabID,
                spaceID: assignment.spaceID,
                profileID: assignment.profileID
            )
        )
    }

    private static func folderItem(
        in assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserSidebarReorderItem {
        .folder(
            BrowserFolderDragItem(
                folderID: FolderID(),
                spaceID: assignment.spaceID,
                profileID: assignment.profileID
            )
        )
    }

    private static func groupItem(
        in assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserSidebarReorderItem {
        .splitGroup(
            BrowserSplitGroupDragItem(
                groupID: SplitGroupID(),
                spaceID: assignment.spaceID,
                profileID: assignment.profileID,
                memberTabIDs: [TabID(), TabID()]
            )
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x50, 0x4C, 0x49, 0x54, 0x44, 0x52, 0x4F,
                0x50, 0x50, 0x4F, 0x4C, 0x49, 0x43, 0x59, finalByte
            )
        )
    }
}
