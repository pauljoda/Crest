import CoreGraphics
import Foundation
import SwiftUI
import XCTest

@testable import Crest

/// "Fancy Move": when a ⇧⌘-held press picks a Split View card up, which slot
/// the gap it leaves is standing in, and how the row is drawn around it.
///
/// The gesture itself is a local `NSEvent` monitor no test can drive, which is
/// exactly why every decision it makes is a pure function. These are the
/// contract for those decisions.
final class BrowserSplitCardLiftPolicyTests: XCTestCase {

    // MARK: - Pickup

    func testAShiftCommandHeldPressInsideACardPicksItUp() {
        XCTAssertTrue(Self.picksUp())
    }

    /// The binding is the pointer's half of ⇧⌘←/→, so it is the same pair.
    func testTheCarryBindingIsTheOneTheMoveShortcutsUse() {
        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.carryModifiers,
            [.command, .shift]
        )
    }

    /// The bare click is how focus moves between cards, and how web content
    /// receives every click anybody makes. Reordering asks for itself.
    func testAPressWithoutModifiersIsAnOrdinaryClick() {
        XCTAssertFalse(Self.picksUp(modifiers: []))
    }

    /// Everything the ⇧⌘ pair is not. Plain ⌘-click still opens a link in a new
    /// tab, ⌥-click still downloads, ⌃-click is still a right-click, and adding
    /// a third modifier to ⇧⌘ hands the press back to the page rather than
    /// widening the carry's claim.
    func testEveryOtherModifierCombinationIsLeftToThePage() {
        XCTAssertFalse(Self.picksUp(modifiers: .command))
        XCTAssertFalse(Self.picksUp(modifiers: .shift))
        XCTAssertFalse(Self.picksUp(modifiers: .option))
        XCTAssertFalse(Self.picksUp(modifiers: .control))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .option]))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .shift, .option]))
        XCTAssertFalse(Self.picksUp(modifiers: [.command, .shift, .control]))
    }

    /// The insets around the row, and the gaps inside it, are not cards.
    func testAPressOutsideEveryCardPicksNothingUp() {
        XCTAssertFalse(Self.picksUp(isInsideCard: false))
    }

    /// The handles overhang the cards they separate, so a press a few points
    /// inside a card's edge is both inside that card and under the control that
    /// resizes it. The resize wins.
    func testTheResizeDividerOutranksAPickup() {
        XCTAssertFalse(Self.picksUp(isOverDivider: true))
    }

    func testALoneCardHasNowhereToGo() {
        XCTAssertFalse(Self.picksUp(memberCount: 1))
    }

    /// Both already own the pointer, exactly as they do for click-to-focus.
    func testASidebarDragAndTheCommandPaletteBothRefuseAPickup() {
        XCTAssertFalse(Self.picksUp(isDraggingSidebarItem: true))
        XCTAssertFalse(Self.picksUp(isCommandPalettePresented: true))
    }

    // MARK: - Divider proximity

    /// The divider's reach is symmetric about the gap between two cards, which
    /// means it covers the last few points of each card as well.
    func testTheDividerClaimsTheGapAndItsOverhangOnEitherSide() {
        let cards = Self.cardFrames(count: 2)
        let gapCenter = (cards[0].maxX + cards[1].minX) / 2
        let reach = BrowserSplitLayoutMetrics.resizeHandleHitWidth / 2

        XCTAssertTrue(Self.isOverDivider(atX: gapCenter, in: cards))
        XCTAssertTrue(Self.isOverDivider(atX: gapCenter - reach + 1, in: cards))
        XCTAssertTrue(Self.isOverDivider(atX: gapCenter + reach - 1, in: cards))
        XCTAssertFalse(Self.isOverDivider(atX: gapCenter - reach - 1, in: cards))
        XCTAssertFalse(Self.isOverDivider(atX: gapCenter + reach + 1, in: cards))
        XCTAssertFalse(Self.isOverDivider(atX: 100, in: cards))
    }

    func testALoneCardHasNoDividerToBeOver() {
        XCTAssertFalse(
            Self.isOverDivider(atX: 150, in: Self.cardFrames(count: 1))
        )
    }

    // MARK: - The gap the carried card leaves

    /// The carried card's own column is the gap, and a gap the pointer is inside
    /// is not a card it has passed. Excluding it is what makes the remaining
    /// `n - 1` neighbours answer in the full `0...n - 1` the row has slots for.
    func testTheGapTracksThePointerAcrossTheCardsItIsNotCarrying() {
        let frames = Self.registeredFrames(count: 3)

        XCTAssertEqual(Self.gapIndex(atX: 10, in: frames, lifted: Self.middle), 0)
        XCTAssertEqual(Self.gapIndex(atX: 149, in: frames, lifted: Self.middle), 0)
        // Past the leading card's midpoint, but nowhere near the trailing one's.
        XCTAssertEqual(Self.gapIndex(atX: 400, in: frames, lifted: Self.middle), 1)
        XCTAssertEqual(Self.gapIndex(atX: 767, in: frames, lifted: Self.middle), 2)
        XCTAssertEqual(
            Self.gapIndex(atX: 5_000, in: frames, lifted: Self.middle),
            2,
            "Overshooting the row parks the gap at the last slot rather than resolving nothing."
        )
    }

    /// Carrying the leading card is not a special case: the two cards left are
    /// measured exactly as any other two would be.
    func testCarryingAnEndCardStillOffersEverySlot() {
        let frames = Self.registeredFrames(count: 3)

        XCTAssertEqual(Self.gapIndex(atX: 10, in: frames, lifted: Self.leading), 0)
        XCTAssertEqual(Self.gapIndex(atX: 500, in: frames, lifted: Self.leading), 1)
        XCTAssertEqual(Self.gapIndex(atX: 800, in: frames, lifted: Self.leading), 2)
    }

    /// A pointer resting over the gap itself resolves to the gap's own slot,
    /// which is what keeps a carry that has not moved from proposing a move.
    func testAPointerOverTheGapProposesTheSlotTheGapIsAlreadyIn() {
        let frames = Self.registeredFrames(count: 3)

        XCTAssertEqual(Self.gapIndex(atX: 458, in: frames, lifted: Self.middle), 1)
    }

    /// The gap moves the cards it passes, and the answer has to survive that or
    /// the slot would flicker under a stationary pointer. Moving the gap toward
    /// the pointer moves the neighbour it passed the other way, which is the
    /// direction that holds the new index.
    func testTheGapSurvivesTheLayoutItsOwnMovementCauses() {
        let members = BrowserSplitCardTestFixture.members
        let widths = [CGFloat](repeating: 300, count: members.count)

        for pointerX in stride(from: CGFloat(5), to: 920, by: 5) {
            let resting = Self.registeredFrames(
                members: members,
                widths: widths
            )
            let index = Self.gapIndex(
                atX: pointerX,
                in: resting,
                lifted: Self.middle
            )
            let shifted = Self.registeredFrames(
                members: BrowserSplitCardLiftPolicy.displayMembers(
                    members,
                    lifted: Self.middle,
                    gapIndex: index
                ),
                widths: widths
            )

            XCTAssertEqual(
                Self.gapIndex(atX: pointerX, in: shifted, lifted: Self.middle),
                index,
                "A pointer at \(pointerX) changed slot once the row shifted around it."
            )
        }
    }

    /// Frames are screen geometry and member order is reading order, and the two
    /// only agree left to right. A mirrored row draws the first member at the
    /// trailing edge, so the count of cards passed is reflected before it is used
    /// as a member index.
    func testAMirroredRowCountsItsSlotsFromTheOtherEnd() {
        let frames = Self.registeredFrames(count: 3)

        XCTAssertEqual(
            Self.gapIndex(
                atX: 10,
                in: frames,
                lifted: Self.middle,
                layoutDirection: .rightToLeft
            ),
            2,
            "The leading edge of a mirrored row is its last member's slot."
        )
        XCTAssertEqual(
            Self.gapIndex(
                atX: 5_000,
                in: frames,
                lifted: Self.middle,
                layoutDirection: .rightToLeft
            ),
            0
        )
    }

    // MARK: - The row as it is drawn

    /// The carried member stays in the list, at its own identity, moved to the
    /// gap. That is what lets a whole reorder happen without remounting the card
    /// — and therefore without handing a live web view to a second superview.
    func testTheCarriedMemberIsMovedRatherThanReplaced() {
        let members = BrowserSplitCardTestFixture.members

        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.displayMembers(
                members,
                lifted: Self.middle,
                gapIndex: 0
            )
            .map(\.id),
            [Self.middle, Self.leading, Self.trailing]
        )
        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.displayMembers(
                members,
                lifted: Self.middle,
                gapIndex: 2
            )
            .map(\.id),
            [Self.leading, Self.trailing, Self.middle]
        )
    }

    func testAGapStillAtItsOriginLeavesTheRowExactlyAsItWas() {
        let members = BrowserSplitCardTestFixture.members

        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.displayMembers(
                members,
                lifted: Self.middle,
                gapIndex: 1
            ),
            members
        )
        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.displayMembers(
                members,
                lifted: nil,
                gapIndex: 0
            ),
            members
        )
    }

    /// The row clamps for the same reason the domain does: a gap resolved past
    /// either end is still that end.
    func testASlotPastEitherEndIsStillThatEnd() {
        let members = BrowserSplitCardTestFixture.members

        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.displayMembers(
                members,
                lifted: Self.leading,
                gapIndex: -4
            )
            .map(\.id),
            [Self.leading, Self.middle, Self.trailing]
        )
        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.displayMembers(
                members,
                lifted: Self.leading,
                gapIndex: 9
            )
            .map(\.id),
            [Self.middle, Self.trailing, Self.leading]
        )
    }

    /// A member that is no longer in the row cannot be moved within it.
    func testAnUnknownCarriedMemberChangesNothing() {
        let members = BrowserSplitCardTestFixture.members

        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.displayMembers(
                members,
                lifted: TabID(),
                gapIndex: 0
            ),
            members
        )
    }

    // MARK: - Where the pointer took hold

    func testTheGrabFractionIsWhereInsideTheCardThePointerLanded() {
        let card = CGRect(x: 100, y: 50, width: 400, height: 200)

        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.grabFraction(
                pointer: CGPoint(x: 300, y: 150),
                in: card
            ),
            CGPoint(x: 0.5, y: 0.5)
        )
        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.grabFraction(
                pointer: CGPoint(x: 100, y: 50),
                in: card
            ),
            CGPoint(x: 0, y: 0)
        )
    }

    /// A pointer outside the card — a frame the row has already animated away
    /// from under it — is still holding one of its edges rather than a point
    /// somewhere off the card entirely.
    func testTheGrabFractionStaysInsideTheCard() {
        let card = CGRect(x: 100, y: 50, width: 400, height: 200)

        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.grabFraction(
                pointer: CGPoint(x: -900, y: 9_000),
                in: card
            ),
            CGPoint(x: 0, y: 1)
        )
        XCTAssertEqual(
            BrowserSplitCardLiftPolicy.grabFraction(
                pointer: .zero,
                in: CGRect(x: 0, y: 0, width: 0, height: 0)
            ),
            CGPoint(x: 0.5, y: 0.5),
            "A card with no size is held in the middle."
        )
    }

    // MARK: - Which cards have a picture to carry

    /// Selecting a split builds a page — and a `WKWebView` — for every member,
    /// start pages included, and a start-page card never loads or mounts the one
    /// it was given. Asking that web view for a picture answers with an empty
    /// one, and an empty picture stands the preview's title-and-favicon
    /// placeholder down: the carry then shows neither the page nor the tab, which
    /// is a card with nothing in it at all.
    func testOnlyACardShowingALivePageHasAPictureToCarry() {
        XCTAssertTrue(BrowserSplitCardLiftPolicy.picturesPage(.livePage))

        for presentation in BrowserPagePresentation.allCases
        where presentation != .livePage {
            XCTAssertFalse(
                BrowserSplitCardLiftPolicy.picturesPage(presentation),
                "\(presentation) draws over a web view that is showing nothing."
            )
        }
    }

    /// The card and its picture must agree about what the card is showing, which
    /// is why both resolve it with the same policy rather than by asking whether
    /// a page happens to exist.
    func testAStartPageCardResolvesToAPresentationWithNoPicture() {
        let presentation = BrowserPagePresentationPolicy.resolve(
            BrowserPagePresentationInput(
                selection: .startPage,
                // A page exists for it, which is exactly the trap: presence is
                // not the same question as what the card is drawing.
                hasActivePage: true,
                hasNavigationFailure: false,
                hasProcessFailure: false,
                unloadedBehavior: .remainUnloaded
            )
        )

        XCTAssertEqual(presentation, .startPage)
        XCTAssertFalse(BrowserSplitCardLiftPolicy.picturesPage(presentation))
    }

    // MARK: - Which card the press landed in

    /// Every card is liftable, and the row has no way to tell one of them apart
    /// from the others. Focus is not among the inputs, so it cannot be among the
    /// answers.
    func testEveryCardInTheRowResolvesTheSameWay() {
        let members = BrowserSplitCardTestFixture.members
        let frames = Self.registeredFrames(count: 3)

        for (index, member) in members.enumerated() {
            let frame = try? XCTUnwrap(frames[member.id])
            let card = BrowserSplitCardLiftPolicy.card(
                at: CGPoint(x: frame?.midX ?? 0, y: 300),
                members: members,
                cardFrames: frames
            )
            XCTAssertEqual(card?.tabID, member.id)
            XCTAssertEqual(card?.index, index)
            XCTAssertEqual(card?.frame, frame)
        }
    }

    /// A frame left behind by a card the row has already closed up around
    /// overlaps the cards that took its place. Resolving through the members
    /// makes it unreachable rather than making it win a dictionary's iteration
    /// order — which is a pickup silently refused, on whichever card the
    /// stranger happened to cover.
    func testAFrameBelongingToNoMemberIsNotACard() {
        let members = Array(BrowserSplitCardTestFixture.members.prefix(2))
        var frames = Self.registeredFrames(count: 2)
        let departed = TabID()
        // The whole row, as the leaving card measured it before it shrank.
        frames[departed] = CGRect(x: 0, y: 0, width: 1_000, height: 600)

        let card = BrowserSplitCardLiftPolicy.card(
            at: CGPoint(x: 150, y: 300),
            members: members,
            cardFrames: frames
        )

        XCTAssertEqual(card?.tabID, members[0].id)
        XCTAssertEqual(card?.index, 0)
    }

    func testAPressOutsideEveryMemberResolvesToNoCard() {
        XCTAssertNil(
            BrowserSplitCardLiftPolicy.card(
                at: CGPoint(x: 5_000, y: 300),
                members: BrowserSplitCardTestFixture.members,
                cardFrames: Self.registeredFrames(count: 3)
            )
        )
    }

    /// A stranger's frame between two members would put a divider's midpoint in
    /// the middle of a card, which reads a whole column as the control that
    /// resizes it and refuses every pickup inside it.
    func testDividerGeometryIgnoresFramesNoMemberOwns() {
        let members = Array(BrowserSplitCardTestFixture.members.prefix(2))
        var frames = Self.registeredFrames(count: 2)
        frames[TabID()] = CGRect(x: 120, y: 0, width: 60, height: 600)

        let ordered = BrowserSplitCardLiftPolicy.orderedMemberFrames(
            members: members,
            cardFrames: frames
        )

        XCTAssertEqual(ordered.count, 2)
        XCTAssertFalse(
            BrowserSplitCardLiftPolicy.isOverDivider(
                CGPoint(x: 150, y: 300),
                orderedCardFrames: ordered
            ),
            "The middle of a card is never a divider."
        )
    }

    // MARK: - Fixtures

    private static let leading = BrowserSplitCardTestFixture.leadingTabID
    private static let middle = BrowserSplitCardTestFixture.middleTabID
    private static let trailing = BrowserSplitCardTestFixture.trailingTabID

    private static func picksUp(
        modifiers: BrowserKeyboardModifierFlags = [.command, .shift],
        isInsideCard: Bool = true,
        isOverDivider: Bool = false,
        memberCount: Int = 2,
        isDraggingSidebarItem: Bool = false,
        isCommandPalettePresented: Bool = false
    ) -> Bool {
        BrowserSplitCardLiftPolicy.picksUp(
            modifiers: modifiers,
            isInsideCard: isInsideCard,
            isOverDivider: isOverDivider,
            memberCount: memberCount,
            isDraggingSidebarItem: isDraggingSidebarItem,
            isCommandPalettePresented: isCommandPalettePresented
        )
    }

    private static func isOverDivider(atX x: CGFloat, in cards: [CGRect]) -> Bool {
        BrowserSplitCardLiftPolicy.isOverDivider(
            CGPoint(x: x, y: 300),
            orderedCardFrames: cards
        )
    }

    private static func gapIndex(
        atX x: CGFloat,
        in frames: [TabID: CGRect],
        lifted: TabID,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> Int {
        BrowserSplitCardLiftPolicy.gapIndex(
            at: CGPoint(x: x, y: 300),
            cardFrames: frames,
            lifted: lifted,
            layoutDirection: layoutDirection
        )
    }

    /// Three 300pt cards with an 8pt gap: midpoints at 150, 458, and 766.
    private static func cardFrames(count: Int) -> [CGRect] {
        frames(widths: Array(repeating: 300, count: count))
    }

    private static func registeredFrames(count: Int) -> [TabID: CGRect] {
        registeredFrames(
            members: Array(BrowserSplitCardTestFixture.members.prefix(count)),
            widths: Array(repeating: 300, count: count)
        )
    }

    /// Card frames as the row would register them for `members` in the order
    /// given: the first member in the leading column, and so on.
    private static func registeredFrames(
        members: [BrowserTab],
        widths: [CGFloat]
    ) -> [TabID: CGRect] {
        Dictionary(
            uniqueKeysWithValues: zip(members.map(\.id), frames(widths: widths))
        )
    }

    private static func frames(widths: [CGFloat]) -> [CGRect] {
        let gap = BrowserSplitLayoutMetrics.interCardGap
        var origin: CGFloat = 0
        var frames: [CGRect] = []
        for width in widths {
            frames.append(CGRect(x: origin, y: 0, width: width, height: 600))
            origin += width + gap
        }
        return frames
    }
}

/// The carry itself: what a pickup stages, what promotes it into a carry, what a
/// pointer sample changes, when the snapshot is allowed to arrive, and what a
/// release, a cancel, and every interruption each leave behind.
@MainActor
final class BrowserSplitCardLiftStateTests: XCTestCase {

    // MARK: - Staging and promotion

    /// The pickup completes without WebKit. The card is carried from the first
    /// frame; the picture is a later improvement to something already moving.
    func testAPickupCarriesTheCardBeforeAnySnapshotExists() {
        let state = BrowserSplitCardLiftState()

        let token = state.reserve()
        XCTAssertTrue(
            state.begin(
                token: token,
                tabID: Self.tabID,
                originIndex: 1,
                cardFrame: Self.cardFrame,
                pointer: CGPoint(x: 500, y: 300),
                surfaceOrigin: Self.surfaceOrigin
            )
        )

        XCTAssertEqual(state.carriedTabID, Self.tabID)
        XCTAssertTrue(state.isCarrying)
        XCTAssertNil(state.lift?.snapshot)
        XCTAssertEqual(state.lift?.gapIndex, 1, "The gap starts where the card was.")
        XCTAssertEqual(state.lift?.cardSize, Self.cardFrame.size)
    }

    /// Staging is inert. A press that turns out to be over a divider, or over no
    /// card, has taken nothing and holds nothing.
    func testAStagedPickupChangesNothingUntilItIsPromoted() {
        let state = BrowserSplitCardLiftState()

        let token = state.reserve()

        XCTAssertNil(state.lift)
        XCTAssertFalse(state.isCarrying)

        state.discard(token)

        XCTAssertNil(state.lift)
        XCTAssertFalse(state.isCarrying)
    }

    /// A discarded pickup cannot be promoted afterwards, however late the
    /// attempt arrives.
    func testADiscardedPickupCannotBecomeACarry() {
        let state = BrowserSplitCardLiftState()
        let token = state.reserve()
        state.discard(token)

        XCTAssertFalse(Self.promote(state, token: token))
        XCTAssertNil(state.lift)
    }

    /// Nor twice: one press is one carry.
    func testOnePickupPromotesOnlyOnce() {
        let state = BrowserSplitCardLiftState()
        let token = state.reserve()

        XCTAssertTrue(Self.promote(state, token: token))
        XCTAssertFalse(Self.promote(state, token: token))
    }

    /// Tokens are never reused, so nothing an earlier carry set in motion can
    /// find its way onto a later one.
    func testEveryPickupGetsAnIdentityOfItsOwn() {
        let state = BrowserSplitCardLiftState()

        let first = state.reserve()
        let second = state.reserve()

        XCTAssertNotEqual(first, second)
        XCTAssertFalse(
            Self.promote(state, token: first),
            "Staging again supersedes the pickup that was staged before it."
        )
        XCTAssertTrue(Self.promote(state, token: second))
    }

    // MARK: - The carry

    /// The preview is placed by arithmetic on the pointer alone, so the point
    /// somebody grabbed is under the cursor at pickup and stays there however
    /// far the card travels.
    func testTheGrabbedPointStaysUnderThePointer() {
        let state = BrowserSplitCardLiftState()
        let grab = CGPoint(x: 500, y: 300)
        let token = state.reserve()
        state.begin(
            token: token,
            tabID: Self.tabID,
            originIndex: 0,
            cardFrame: Self.cardFrame,
            pointer: grab,
            surfaceOrigin: Self.surfaceOrigin
        )

        XCTAssertEqual(
            Self.grabbedPoint(in: state),
            CGPoint(
                x: Self.surfaceOrigin.x + grab.x,
                y: Self.surfaceOrigin.y + grab.y
            )
        )

        state.update(
            pointer: CGPoint(x: 120, y: 480),
            gapIndex: 0,
            surfaceOrigin: Self.surfaceOrigin
        )

        XCTAssertEqual(
            Self.grabbedPoint(in: state),
            CGPoint(x: Self.surfaceOrigin.x + 120, y: Self.surfaceOrigin.y + 480)
        )
    }

    func testAPointerSampleMovesTheGapWithIt() {
        let state = Self.carryingState()

        state.update(
            pointer: CGPoint(x: 800, y: 320),
            gapIndex: 2,
            surfaceOrigin: Self.surfaceOrigin
        )

        XCTAssertEqual(state.lift?.pointer, CGPoint(x: 800, y: 320))
        XCTAssertEqual(state.lift?.gapIndex, 2)
    }

    // MARK: - The picture

    func testTheSnapshotCrossfadesInWhenWebKitAnswers() {
        let state = BrowserSplitCardLiftState()
        let token = state.reserve()
        Self.promote(state, token: token)

        state.attach(snapshot: Self.image, token: token)

        XCTAssertEqual(state.lift?.snapshot, Self.image)
    }

    /// A picture asked for by a pickup that never became a carry belongs to
    /// nothing on screen.
    func testASnapshotForADiscardedPickupIsRefused() {
        let state = BrowserSplitCardLiftState()
        let refused = state.reserve()
        state.discard(refused)
        let carried = state.reserve()
        Self.promote(state, token: carried)

        state.attach(snapshot: Self.image, token: refused)

        XCTAssertNil(state.lift?.snapshot)
    }

    /// Picking the same card up twice in quick succession leaves the first
    /// request in flight. Its answer pictures a row that has already moved on.
    func testASnapshotFromAnEarlierCarryOfTheSameCardIsRefused() {
        let state = BrowserSplitCardLiftState()
        let first = state.reserve()
        Self.promote(state, token: first)
        _ = state.drop()
        let second = state.reserve()
        Self.promote(state, token: second)

        state.attach(snapshot: Self.image, token: first)

        XCTAssertNil(
            state.lift?.snapshot,
            "The tab matches; the carry does not, which is the answer that counts."
        )

        state.attach(snapshot: Self.image, token: second)

        XCTAssertEqual(state.lift?.snapshot, Self.image)
    }

    /// The preview is still on screen while it descends, so a picture that lands
    /// a frame late is still worth showing. Refusing it is how a short press ends
    /// up having shown nothing but an empty card for its whole life.
    func testASnapshotArrivingDuringTheSettleIsStillShown() {
        let state = BrowserSplitCardLiftState()
        let token = state.reserve()
        Self.promote(state, token: token)
        _ = state.drop()

        state.attach(snapshot: Self.image, token: token)

        XCTAssertEqual(state.lift?.snapshot, Self.image)
    }

    // MARK: - Release, cancel, abandon

    /// The release hands back the slot the gap was standing in — the same index
    /// the row has already drawn — and stops the carry, which is what puts the
    /// card back on show under the settling preview.
    func testAReleaseCommitsTheSlotTheGapIsStandingIn() {
        let state = Self.carryingState()
        state.update(
            pointer: CGPoint(x: 800, y: 320),
            gapIndex: 2,
            surfaceOrigin: Self.surfaceOrigin
        )

        let move = state.drop()

        XCTAssertEqual(move?.tabID, Self.tabID)
        XCTAssertEqual(move?.memberIndex, 2)
        XCTAssertEqual(state.lift?.isSettling, true)
        XCTAssertNil(state.carriedTabID, "A settling card is back in the row.")
        XCTAssertFalse(state.isCarrying)
    }

    /// Nothing may be committed twice: the second release of one carry is a
    /// release of nothing.
    func testASecondReleaseCommitsNothing() {
        let state = Self.carryingState()
        _ = state.drop()

        XCTAssertNil(state.drop())
    }

    /// Escape and a right-click end the carry without a move, and without ever
    /// having made one: nothing here has touched the session.
    func testACancelReturnsTheCardWithoutAMove() {
        let state = Self.carryingState()
        state.update(
            pointer: CGPoint(x: 800, y: 320),
            gapIndex: 2,
            surfaceOrigin: Self.surfaceOrigin
        )

        state.cancel()

        XCTAssertEqual(state.lift?.isSettling, true)
        XCTAssertNil(state.carriedTabID)
        XCTAssertEqual(
            state.lift?.originIndex,
            1,
            "The row puts the card back where the carry found it."
        )
    }

    /// A settling preview is not a carry, so nothing may restart one.
    func testASettlingCarryTakesNoMorePointerSamples() {
        let state = Self.carryingState()
        state.cancel()

        state.update(
            pointer: CGPoint(x: 900, y: 100),
            gapIndex: 0,
            surfaceOrigin: Self.surfaceOrigin
        )

        XCTAssertEqual(state.lift?.gapIndex, 1)
    }

    /// A card that left the row has nothing to settle onto.
    func testAbandoningACarryLeavesNothingBehind() {
        let state = Self.carryingState()

        state.abandon()

        XCTAssertNil(state.lift)
        XCTAssertFalse(state.isCarrying)
    }

    // MARK: - Totality

    /// Every way a pickup can be refused, and every way a carry can be
    /// interrupted, returns the state to idle — and a pickup made straight
    /// afterwards succeeds.
    ///
    /// This is the property the whole state machine exists for. A window that
    /// can never pick a card up again is a window holding one refused or
    /// interrupted transition that left something armed, so each of them is
    /// enumerated here rather than argued about.
    func testEveryRefusedOrInterruptedTransitionReturnsToIdle() {
        let interruptions: [(String, (BrowserSplitCardLiftState) -> Void)] = [
            (
                "a pickup refused before it was promoted",
                { state in
                    state.discard(state.reserve())
                }
            ),
            (
                "a pickup refused twice over",
                { state in
                    let token = state.reserve()
                    state.discard(token)
                    state.discard(token)
                }
            ),
            (
                "a cancel with nothing in flight",
                { state in
                    state.cancel()
                }
            ),
            (
                "a cancel of a staged pickup",
                { state in
                    _ = state.reserve()
                    state.cancel()
                }
            ),
            (
                "a release with nothing in flight",
                { state in
                    XCTAssertNil(state.drop())
                }
            ),
            (
                "an abandon with nothing in flight",
                { state in
                    state.abandon()
                }
            ),
            (
                "a carry released",
                { state in
                    Self.promote(state, token: state.reserve())
                    _ = state.drop()
                }
            ),
            (
                "a carry cancelled",
                { state in
                    Self.promote(state, token: state.reserve())
                    state.cancel()
                }
            ),
            (
                "a carry cancelled twice",
                { state in
                    Self.promote(state, token: state.reserve())
                    state.cancel()
                    state.cancel()
                }
            ),
            (
                "a carry released and then cancelled",
                { state in
                    Self.promote(state, token: state.reserve())
                    _ = state.drop()
                    state.cancel()
                }
            ),
            (
                "a carry abandoned mid-flight",
                { state in
                    Self.promote(state, token: state.reserve())
                    state.abandon()
                }
            ),
            (
                "a carry abandoned while settling",
                { state in
                    Self.promote(state, token: state.reserve())
                    _ = state.drop()
                    state.abandon()
                }
            ),
            (
                "a snapshot arriving for nothing",
                { state in
                    state.attach(snapshot: Self.image, token: state.reserve())
                }
            ),
        ]

        for (description, interruption) in interruptions {
            let state = BrowserSplitCardLiftState()
            interruption(state)

            XCTAssertFalse(
                state.isCarrying,
                "\(description) left the pointer believing it holds a card."
            )

            let token = state.reserve()

            XCTAssertTrue(
                state.begin(
                    token: token,
                    tabID: Self.tabID,
                    originIndex: 1,
                    cardFrame: Self.cardFrame,
                    pointer: CGPoint(x: 500, y: 300),
                    surfaceOrigin: Self.surfaceOrigin
                ),
                "No card could be picked up after \(description)."
            )
            XCTAssertEqual(state.carriedTabID, Self.tabID)
            XCTAssertTrue(state.isCarrying)
        }
    }

    /// A pickup made while another carry is still settling supersedes it
    /// outright rather than inheriting anything from it.
    func testAPickupDuringASettleStartsCleanly() {
        let state = Self.carryingState()
        state.update(
            pointer: CGPoint(x: 800, y: 320),
            gapIndex: 2,
            surfaceOrigin: Self.surfaceOrigin
        )
        state.attach(snapshot: Self.image, token: Self.token(of: state))
        _ = state.drop()

        let token = state.reserve()
        state.begin(
            token: token,
            tabID: Self.otherTabID,
            originIndex: 0,
            cardFrame: Self.cardFrame,
            pointer: CGPoint(x: 100, y: 100),
            surfaceOrigin: Self.surfaceOrigin
        )

        XCTAssertEqual(state.carriedTabID, Self.otherTabID)
        XCTAssertEqual(state.lift?.gapIndex, 0)
        XCTAssertNil(state.lift?.snapshot, "The new carry has no picture yet.")
        XCTAssertEqual(state.lift?.isSettling, false)
    }

    // MARK: - Fixtures

    private static let tabID = BrowserSplitCardTestFixture.middleTabID
    private static let otherTabID = BrowserSplitCardTestFixture.leadingTabID
    private static let cardFrame = CGRect(x: 308, y: 0, width: 400, height: 600)
    private static let surfaceOrigin = CGPoint(x: 260, y: 40)
    private static let image = NSImage(size: CGSize(width: 4, height: 4))

    private static func carryingState() -> BrowserSplitCardLiftState {
        let state = BrowserSplitCardLiftState()
        promote(state, token: state.reserve())
        return state
    }

    @discardableResult
    private static func promote(
        _ state: BrowserSplitCardLiftState,
        token: BrowserSplitCardLiftToken
    ) -> Bool {
        state.begin(
            token: token,
            tabID: tabID,
            originIndex: 1,
            cardFrame: cardFrame,
            pointer: CGPoint(x: 500, y: 300),
            surfaceOrigin: surfaceOrigin
        )
    }

    private static func token(of state: BrowserSplitCardLiftState) -> BrowserSplitCardLiftToken {
        state.lift?.token ?? BrowserSplitCardLiftToken(sequence: 0)
    }

    /// Where the point somebody grabbed has ended up, in the preview window's
    /// coordinates: the preview's origin plus the grabbed fraction of the card.
    private static func grabbedPoint(in state: BrowserSplitCardLiftState) -> CGPoint? {
        guard let lift = state.lift else { return nil }
        return CGPoint(
            x: lift.previewOrigin.x + lift.grabFraction.x * lift.cardSize.width,
            y: lift.previewOrigin.y + lift.grabFraction.y * lift.cardSize.height
        )
    }
}

private enum BrowserSplitCardTestFixture {
    static let leadingTabID = tabID(0x11)
    static let middleTabID = tabID(0x12)
    static let trailingTabID = tabID(0x13)

    static let members = [
        member(id: leadingTabID, title: "Release Notes"),
        member(id: middleTabID, title: "Layout Research"),
        member(id: trailingTabID, title: "Split View Spec"),
    ]

    private static let groupID = SplitGroupID(rawValue: uuid(0x01))

    private static func member(id: TabID, title: String) -> BrowserTab {
        BrowserTab(
            id: id,
            title: title,
            url: URL(fileURLWithPath: "/split-card-tests/\(id.rawValue.uuidString)"),
            symbol: "globe",
            placement: .current,
            splitGroupID: groupID,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private static func tabID(_ finalByte: UInt8) -> TabID {
        TabID(rawValue: uuid(finalByte))
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x54,
                0x45, 0x53,
                0x54, 0x53,
                0x50, 0x4C, 0x49, 0x54, 0x00, finalByte
            ))
    }
}
