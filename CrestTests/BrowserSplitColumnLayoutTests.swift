import CoreGraphics
import Foundation
import XCTest

@testable import Crest

/// The column arithmetic behind Split View.
///
/// Every case checks the two invariants the layout promises — non-negative
/// widths that sum to the container's available width — alongside the specific
/// behavior under test, because a rule that holds locally and breaks the total
/// still ships a visibly wrong window.
final class BrowserSplitColumnLayoutTests: XCTestCase {
    private let gap: CGFloat = BrowserSplitLayoutMetrics.interCardGap
    private let minimum: CGFloat = BrowserSplitLayoutMetrics.minimumCardWidth

    func testFocusedCardDrawsAboveItsRestingSiblings() {
        XCTAssertGreaterThan(
            BrowserSplitLayoutMetrics.focusedCardZIndex,
            BrowserSplitLayoutMetrics.restingCardZIndex
        )
    }

    // MARK: - Widths

    func testEqualFractionsShareTheWidthLeftByTheGaps() {
        let widths = makeWidths(containerWidth: 1000, fractions: [1, 1, 1])

        assertWidths(widths, sumTo: 1000 - gap * 2)
        XCTAssertEqual(widths[0], widths[1], accuracy: 0.0001)
        XCTAssertEqual(widths[1], widths[2], accuracy: 0.0001)
    }

    func testUnnormalizedFractionsLayOutLikeTheirNormalizedForm() {
        let raw = makeWidths(containerWidth: 1000, fractions: [2, 1, 1])
        let normalized = makeWidths(containerWidth: 1000, fractions: [0.5, 0.25, 0.25])

        assertWidths(raw, sumTo: 1000 - gap * 2)
        for (rawWidth, normalizedWidth) in zip(raw, normalized) {
            XCTAssertEqual(rawWidth, normalizedWidth, accuracy: 0.0001)
        }
        XCTAssertEqual(raw[0], 492, accuracy: 0.0001)
        XCTAssertEqual(raw[1], 246, accuracy: 0.0001)
    }

    func testACardTooNarrowForItsShareIsFlooredAtTheMinimum() {
        let widths = makeWidths(containerWidth: 1000, fractions: [0.95, 0.05])

        assertWidths(widths, sumTo: 1000 - gap)
        XCTAssertEqual(widths[1], minimum, accuracy: 0.0001)
        XCTAssertEqual(
            widths[0],
            1000 - gap - minimum,
            accuracy: 0.0001,
            "Flooring one card gives the width it took back to the others."
        )
    }

    func testFlooringRedistributesToEveryCardStillAboveTheFloor() {
        let widths = makeWidths(containerWidth: 1400, fractions: [0.5, 0.4, 0.05, 0.05])

        assertWidths(widths, sumTo: 1400 - gap * 3)
        XCTAssertEqual(widths[2], minimum, accuracy: 0.0001)
        XCTAssertEqual(widths[3], minimum, accuracy: 0.0001)
        XCTAssertEqual(
            widths[0] / widths[1],
            0.5 / 0.4,
            accuracy: 0.0001,
            "The cards that absorb the overflow keep their relative shares."
        )
    }

    func testAContainerTooNarrowForItsCardsFloorsThemAndClips() {
        for containerWidth in [CGFloat(0), -500, 120, 400] {
            let widths = makeWidths(containerWidth: containerWidth, fractions: [0.5, 0.5])

            XCTAssertEqual(
                widths,
                [minimum, minimum],
                "A narrow window clips its cards; it never dissolves the split."
            )
        }
    }

    func testAContainerExactlyAsWideAsTheFloorsStillTotals() {
        let containerWidth = minimum * 3 + gap * 2
        let widths = makeWidths(containerWidth: containerWidth, fractions: [0.6, 0.2, 0.2])

        XCTAssertEqual(widths, [minimum, minimum, minimum])
        assertWidths(widths, sumTo: containerWidth - gap * 2)
    }

    func testASingleCardTakesTheWholeContainerWithNoGapToPay() {
        assertWidths(makeWidths(containerWidth: 900, fractions: [1]), sumTo: 900)
        XCTAssertEqual(makeWidths(containerWidth: 900, fractions: [0.4]), [900])
        XCTAssertEqual(makeWidths(containerWidth: 900, fractions: []), [])
    }

    func testMalformedFractionsFallBackToEqualColumns() {
        for fractions in [[Double.nan, 0.5], [0, 1], [-0.5, 1.5], [.infinity, 1]] {
            let widths = makeWidths(containerWidth: 1000, fractions: fractions)

            assertWidths(widths, sumTo: 1000 - gap)
            XCTAssertEqual(widths[0], widths[1], accuracy: 0.0001)
        }
        XCTAssertEqual(
            BrowserSplitColumnLayout.normalizedFractions([Double.nan, 0.5]),
            BrowserSplitColumnLayout.equalFractions(count: 2)
        )
    }

    // MARK: - Resize

    func testADragMovesOnlyThePairAroundItsDivider() {
        let fractions = BrowserSplitColumnLayout.equalFractions(count: 3)

        let resized = makeResize(fractions: fractions, dividerIndex: 1, delta: 50)

        assertFractionsSumToOne(resized)
        XCTAssertEqual(
            resized[0],
            fractions[0],
            accuracy: 0.0001,
            "A card that does not touch the divider keeps its width."
        )
        let available = 1000 - gap * 2
        XCTAssertEqual(resized[1], fractions[1] + 50 / available, accuracy: 0.0001)
        XCTAssertEqual(resized[2], fractions[2] - 50 / available, accuracy: 0.0001)
    }

    func testADragStopsWhenEitherSideReachesTheMinimum() {
        let fractions = BrowserSplitColumnLayout.equalFractions(count: 2)
        let available = 1000 - gap

        let shrunk = makeResize(fractions: fractions, dividerIndex: 0, delta: -1000)
        assertFractionsSumToOne(shrunk)
        XCTAssertEqual(shrunk[0], minimum / available, accuracy: 0.0001)
        XCTAssertEqual(shrunk[1], (available - minimum) / available, accuracy: 0.0001)

        let grown = makeResize(fractions: fractions, dividerIndex: 0, delta: 1000)
        assertFractionsSumToOne(grown)
        XCTAssertEqual(grown[0], (available - minimum) / available, accuracy: 0.0001)
        XCTAssertEqual(grown[1], minimum / available, accuracy: 0.0001)
    }

    func testEveryDividerSitsCenteredOnTheGapItMoves() {
        let widths = makeWidths(containerWidth: 1000, fractions: [0.5, 0.25, 0.25])
        let handleWidth = BrowserSplitLayoutMetrics.resizeHandleHitWidth

        for dividerIndex in 0..<2 {
            let leading = BrowserSplitColumnLayout.dividerLeadingDistance(
                after: dividerIndex,
                cardWidths: widths,
                gap: gap,
                handleWidth: handleWidth
            )
            let cards = widths.prefix(dividerIndex + 1).reduce(0, +)
            XCTAssertEqual(
                leading + handleWidth / 2,
                cards + gap * CGFloat(dividerIndex) + gap / 2,
                accuracy: 0.0001,
                "The handle's hit width is centered on the gap after its card."
            )
        }
    }

    func testTheDividerFollowsTheDragThatMovesIt() {
        let fractions = BrowserSplitColumnLayout.equalFractions(count: 2)
        let before = makeDividerDistance(fractions: fractions)

        let after = makeDividerDistance(
            fractions: makeResize(fractions: fractions, dividerIndex: 0, delta: 60)
        )

        XCTAssertEqual(
            after - before,
            60,
            accuracy: 0.0001,
            """
            The handle is positioned from the fractions its own drag writes, \
            which is why the drag is measured in the row's space and never in \
            the handle's.
            """
        )
    }

    func testEveryDividerResizesAndOutOfRangeDividersDoNot() {
        let fractions = BrowserSplitColumnLayout.equalFractions(count: 4)

        for dividerIndex in 0..<3 {
            let resized = makeResize(
                fractions: fractions,
                dividerIndex: dividerIndex,
                delta: 30,
                containerWidth: 1600
            )

            assertFractionsSumToOne(resized)
            assertWidths(
                makeWidths(containerWidth: 1600, fractions: resized),
                sumTo: 1600 - gap * 3
            )
            XCTAssertGreaterThan(resized[dividerIndex], fractions[dividerIndex])
            XCTAssertLessThan(resized[dividerIndex + 1], fractions[dividerIndex + 1])
            for untouched in 0..<4 where untouched != dividerIndex && untouched != dividerIndex + 1 {
                XCTAssertEqual(resized[untouched], fractions[untouched], accuracy: 0.0001)
            }
        }

        for dividerIndex in [-1, 3, 9] {
            XCTAssertEqual(
                makeResize(fractions: fractions, dividerIndex: dividerIndex, delta: 30),
                fractions,
                "Only the gaps between two cards are dividers."
            )
        }
    }

    func testAPairWithNoRoomToGiveIgnoresTheDrag() {
        let fractions = BrowserSplitColumnLayout.equalFractions(count: 2)

        XCTAssertEqual(
            makeResize(fractions: fractions, dividerIndex: 0, delta: 40, containerWidth: 300),
            fractions
        )
        XCTAssertEqual(
            makeResize(fractions: fractions, dividerIndex: 0, delta: 40, containerWidth: 0),
            fractions
        )
    }

    // MARK: - Membership changes

    func testAJoiningCardTakesAnEqualShareOfTheWiderSplit() {
        let inserted = BrowserSplitColumnLayout.fractionsInserting(
            at: 1,
            into: [0.5, 0.5]
        )

        assertFractionsSumToOne(inserted)
        XCTAssertEqual(inserted.count, 3)
        for share in inserted {
            XCTAssertEqual(share, 1.0 / 3, accuracy: 0.0001)
        }
    }

    func testAJoiningCardLeavesTheExistingCardsAsLopsidedAsTheyWere() {
        let inserted = BrowserSplitColumnLayout.fractionsInserting(at: 0, into: [0.7, 0.3])

        assertFractionsSumToOne(inserted)
        XCTAssertEqual(inserted[0], 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(inserted[1] / inserted[2], 0.7 / 0.3, accuracy: 0.0001)
    }

    func testInsertionClampsItsIndexAndSeedsAnEmptySplit() {
        XCTAssertEqual(
            BrowserSplitColumnLayout.fractionsInserting(at: 9, into: [0.5, 0.5]).count,
            3
        )
        XCTAssertEqual(BrowserSplitColumnLayout.fractionsInserting(at: -3, into: [1]).count, 2)
        XCTAssertEqual(BrowserSplitColumnLayout.fractionsInserting(at: 0, into: []), [1])
    }

    func testALeavingCardHandsItsShareBackProportionally() {
        let removed = BrowserSplitColumnLayout.fractionsRemoving(at: 1, from: [0.6, 0.3, 0.1])

        assertFractionsSumToOne(removed)
        XCTAssertEqual(removed[0], 0.6 / 0.7, accuracy: 0.0001)
        XCTAssertEqual(removed[1], 0.1 / 0.7, accuracy: 0.0001)
    }

    func testRemovalHandlesTheLastCardAndAnIndexThatIsNotThere() {
        XCTAssertEqual(BrowserSplitColumnLayout.fractionsRemoving(at: 0, from: [1]), [])
        XCTAssertEqual(
            BrowserSplitColumnLayout.fractionsRemoving(at: 4, from: [0.5, 0.5]),
            [0.5, 0.5]
        )
    }

    // MARK: - Drag placeholder

    /// The whole point of the drop column: it is not a hint, it is the joining
    /// card's own column drawn early, so it has to be exactly the width that
    /// card will have.
    func testThePlaceholderBesideALoneCardIsExactlyHalfTheRow() {
        let widths = makeInsertionWidths(
            containerWidth: 1200,
            fractions: [1],
            index: 1
        )

        assertWidths(widths, sumTo: 1200 - gap)
        XCTAssertEqual(widths, [596, 596])
        XCTAssertEqual(
            widths,
            makeWidths(containerWidth: 1200, fractions: [0.5, 0.5]),
            "The drag lays out the split the drop is about to commit."
        )
    }

    func testThePlaceholderTakesAThirdBesideTwoAndAQuarterBesideThree() {
        let thirds = makeInsertionWidths(
            containerWidth: 1200,
            fractions: [0.5, 0.5],
            index: 1
        )
        assertWidths(thirds, sumTo: 1200 - gap * 2)
        for width in thirds {
            XCTAssertEqual(width, (1200 - gap * 2) / 3, accuracy: 0.0001)
        }

        let quarters = makeInsertionWidths(
            containerWidth: 1200,
            fractions: [1, 1, 1],
            index: 2
        )
        assertWidths(quarters, sumTo: 1200 - gap * 3)
        for width in quarters {
            XCTAssertEqual(width, (1200 - gap * 3) / 4, accuracy: 0.0001)
        }
    }

    /// Every slot is a column, so the drop column floors at the same minimum a
    /// card does and the window clips rather than dissolving the split.
    func testTheDropColumnFloorsAtTheMinimumLikeEveryOtherColumn() {
        let widths = makeInsertionWidths(
            containerWidth: 900,
            fractions: [1, 1, 1],
            index: 0
        )

        XCTAssertEqual(widths, [minimum, minimum, minimum, minimum])
    }

    /// A resized split gives the newcomer an equal share and keeps its own
    /// lopsidedness, and the row still fills the window exactly while it does.
    func testAResizedSplitKeepsItsProportionsAroundTheDropColumn() {
        let widths = makeInsertionWidths(
            containerWidth: 1600,
            fractions: [0.6, 0.4],
            index: 1
        )

        assertWidths(widths, sumTo: 1600 - gap * 2)
        XCTAssertEqual(widths[1], (1600 - gap * 2) / 3, accuracy: 0.0001)
        XCTAssertEqual(widths[0] / widths[2], 0.6 / 0.4, accuracy: 0.0001)
    }

    /// Nothing on show is a one-column row, and a one-column row has no gap to
    /// pay for. A window too narrow even for that floors and clips, exactly as a
    /// real card does — the drop column is not a special kind of column.
    func testAnEmptySplitGivesThePlaceholderTheWholeRow() {
        XCTAssertEqual(
            makeInsertionWidths(containerWidth: 900, fractions: [], index: 0),
            [900]
        )
        XCTAssertEqual(
            makeInsertionWidths(containerWidth: 200, fractions: [], index: 0),
            [minimum]
        )
    }

    // MARK: - Slots

    /// The row is one list of columns. The drop column is inserted into it, not
    /// laid beside it, which is what makes the widths above the widths the row
    /// actually draws.
    func testTheDropColumnIsInsertedIntoTheMemberList() {
        let members = [makeTab(0x01), makeTab(0x02)]

        XCTAssertEqual(
            BrowserSplitColumnSlot.slots(members: members, placeholderIndex: 1)
                .map(\.id),
            [.member(members[0].id), .placeholder, .member(members[1].id)]
        )
        XCTAssertEqual(
            BrowserSplitColumnSlot.slots(members: members, placeholderIndex: 2)
                .map(\.id),
            [.member(members[0].id), .member(members[1].id), .placeholder]
        )
        XCTAssertEqual(
            BrowserSplitColumnSlot.slots(members: members, placeholderIndex: 0)
                .map(\.member?.id),
            [nil, members[0].id, members[1].id]
        )
    }

    /// An index no drag resolved — and one outside the row — is not a column, so
    /// the row lays out as it does at rest.
    func testAnIndexOutsideTheRowOpensNoColumn() {
        let members = [makeTab(0x01), makeTab(0x02)]

        for index in [nil, -1, 3, 12] {
            XCTAssertEqual(
                BrowserSplitColumnSlot.slots(
                    members: members,
                    placeholderIndex: index
                )
                .map(\.id),
                members.map { .member($0.id) },
                "\(String(describing: index)) opened a column."
            )
        }
    }

    // MARK: - Width transaction

    func testResizingKeepsIntermediateFractionsOutOfTheDurableRecord() {
        var transaction = BrowserSplitWidthTransaction(persistedFractions: [0.5, 0.5])
        let available = 1000 - gap

        transaction.resize(dividerIndex: 0, delta: 40, containerWidth: 1000)
        transaction.resize(dividerIndex: 0, delta: 90, containerWidth: 1000)

        XCTAssertEqual(
            transaction.fractions[0],
            (available / 2 + 90) / available,
            accuracy: 0.0001,
            "A drag reports total travel, so the frames must not compound."
        )
        XCTAssertEqual(transaction.persistedFractions, [0.5, 0.5])

        let committed = transaction.commit()

        XCTAssertEqual(committed, transaction.fractions)
        XCTAssertEqual(transaction.persistedFractions, transaction.fractions)
        XCTAssertNil(transaction.commit(), "A committed layout has nothing left to write.")
    }

    func testCommitAnswersNilWhenTheDragChangedNothingWorthWriting() {
        var transaction = BrowserSplitWidthTransaction(persistedFractions: [0.5, 0.5])

        transaction.resize(dividerIndex: 0, delta: 0, containerWidth: 1000)
        XCTAssertNil(transaction.commit())

        transaction.resize(dividerIndex: 0, delta: 0.1, containerWidth: 1000)
        XCTAssertNil(transaction.commit(), "Pointer noise is not a layout change.")

        transaction.resize(dividerIndex: 0, delta: 60, containerWidth: 1000)
        XCTAssertNotNil(transaction.commit())
    }

    func testBeginAdoptsTheIncomingFractionsAndDropsTheDragInFlight() {
        var transaction = BrowserSplitWidthTransaction(persistedFractions: [0.5, 0.5])
        let available = 1000 - gap

        transaction.resize(dividerIndex: 0, delta: 120, containerWidth: 1000)
        transaction.begin(fractions: [0.25, 0.75])

        XCTAssertEqual(transaction.fractions, [0.25, 0.75])
        XCTAssertEqual(transaction.persistedFractions, [0.25, 0.75])
        XCTAssertNil(transaction.commit())

        transaction.resize(dividerIndex: 0, delta: 50, containerWidth: 1000)

        XCTAssertEqual(
            transaction.fractions[0],
            (available * 0.25 + 50) / available,
            accuracy: 0.0001,
            "The next drag measures from the layout begin installed."
        )
    }

    func testATransactionNormalizesWhateverThePersistedRecordHeld() {
        var transaction = BrowserSplitWidthTransaction(persistedFractions: [2, 1, 1])

        XCTAssertEqual(transaction.fractions, [0.5, 0.25, 0.25])
        XCTAssertNil(transaction.commit())

        transaction.begin(fractions: [0, -1])

        XCTAssertEqual(transaction.fractions, [0.5, 0.5])
    }

    // MARK: - Helpers

    private func makeTab(_ finalByte: UInt8) -> BrowserTab {
        BrowserTab(
            id: TabID(
                rawValue: UUID(
                    uuid: (
                        0x53, 0x50, 0x4C, 0x49, 0x54, 0x43, 0x4F, 0x4C,
                        0x55, 0x4D, 0x4E, 0x53, 0x4C, 0x4F, 0x54, finalByte
                    )
                )
            ),
            title: "Card \(finalByte)",
            url: URL(string: "https://example.com/\(finalByte)"),
            symbol: "globe",
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeWidths(
        containerWidth: CGFloat,
        fractions: [Double]
    ) -> [CGFloat] {
        BrowserSplitColumnLayout.widths(
            containerWidth: containerWidth,
            fractions: fractions,
            gap: gap,
            minimum: minimum
        )
    }

    private func makeDividerDistance(
        fractions: [Double],
        dividerIndex: Int = 0,
        containerWidth: CGFloat = 1000
    ) -> CGFloat {
        BrowserSplitColumnLayout.dividerLeadingDistance(
            after: dividerIndex,
            cardWidths: makeWidths(containerWidth: containerWidth, fractions: fractions),
            gap: gap,
            handleWidth: BrowserSplitLayoutMetrics.resizeHandleHitWidth
        )
    }

    private func makeResize(
        fractions: [Double],
        dividerIndex: Int,
        delta: CGFloat,
        containerWidth: CGFloat = 1000
    ) -> [Double] {
        BrowserSplitColumnLayout.fractionsAfterResize(
            fractions: fractions,
            dividerIndex: dividerIndex,
            delta: delta,
            containerWidth: containerWidth,
            gap: gap,
            minimum: minimum
        )
    }

    /// The widths a drag in flight lays out, composed exactly as
    /// `BrowserSplitColumnsView` composes them: the fractions the joining card
    /// produces, spread across the same container.
    private func makeInsertionWidths(
        containerWidth: CGFloat,
        fractions: [Double],
        index: Int
    ) -> [CGFloat] {
        makeWidths(
            containerWidth: containerWidth,
            fractions: BrowserSplitColumnLayout.fractionsInserting(
                at: index,
                into: fractions
            )
        )
    }

    private func assertWidths(
        _ widths: [CGFloat],
        sumTo total: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for width in widths {
            XCTAssertGreaterThanOrEqual(width, 0, file: file, line: line)
        }
        XCTAssertEqual(widths.reduce(0, +), total, accuracy: 0.0001, file: file, line: line)
    }

    private func assertFractionsSumToOne(
        _ fractions: [Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for fraction in fractions {
            XCTAssertGreaterThan(fraction, 0, file: file, line: line)
        }
        XCTAssertEqual(fractions.reduce(0, +), 1, accuracy: 0.0001, file: file, line: line)
    }
}
