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

    // MARK: - Widths

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
