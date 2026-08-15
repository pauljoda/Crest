import CoreGraphics
import Foundation
import XCTest

@testable import Crest

/// The width transaction's interaction lifecycle.
///
/// The first section is the regression guard for the resize feedback loop. A
/// divider handle is positioned from the fractions its own drag writes, so a
/// gesture measured against that handle reports the pointer's travel minus the
/// handle's, and the layout never settles. These cases fix the two halves of the
/// fix in arithmetic: a drag holding one pointer position must answer the same
/// fractions on every layout pass, and the divider that pass positions must come
/// to rest. The rest of the class guards the commit contract per-window
/// persistence depends on.
final class BrowserSplitWidthTransactionTests: XCTestCase {
    private let containerWidth: CGFloat = 1000
    /// How many times a real drag can be re-evaluated while the pointer sits
    /// still: enough passes that a loop with any gain at all would show.
    private let layoutPasses = 32

    // MARK: - Stability under a stationary pointer

    func testAStationaryPointerLeavesTheLayoutWhereItIs() {
        var transaction = makeTransaction()
        let travel: CGFloat = 120

        transaction.resize(dividerIndex: 0, delta: travel, containerWidth: containerWidth)
        let settled = transaction.fractions
        for _ in 0..<layoutPasses {
            transaction.resize(dividerIndex: 0, delta: travel, containerWidth: containerWidth)
        }

        assertFractions(
            transaction.fractions,
            equal: settled,
            "The same total travel has to answer the same layout on every pass."
        )
    }

    /// The whole loop, closed: measure a stationary pointer against the divider
    /// the last pass drew, feed that back, and repeat.
    ///
    /// This is what the old `.local` gesture did. Measuring in the row's space
    /// instead makes the reported travel independent of where the divider ended
    /// up, so the boundary lands on the pointer and stays there.
    func testTheDividerConvergesOnThePointerItIsMeasuredAgainst() {
        var transaction = BrowserSplitWidthTransaction(persistedFractions: [0.5, 0.5])
        let grabbed = dividerPosition(of: transaction)
        let pointer = grabbed + 120

        var positions: [CGFloat] = []
        for _ in 0..<layoutPasses {
            // The row's space: total travel from where the drag began, which no
            // amount of divider movement can change.
            transaction.resize(
                dividerIndex: 0,
                delta: pointer - grabbed,
                containerWidth: containerWidth
            )
            positions.append(dividerPosition(of: transaction))
        }

        guard let landed = positions.last else { return XCTFail("No layout passes ran.") }
        XCTAssertEqual(
            landed,
            pointer,
            accuracy: 0.5,
            "The boundary has to arrive under the pointer, not at a fraction of its travel."
        )
        for position in positions {
            XCTAssertEqual(
                position,
                landed,
                accuracy: 0.0001,
                "Every pass has to draw the same divider: an oscillation is a moving one."
            )
        }
    }

    /// The same loop with the divider's own frame in it, which is the regression
    /// itself: a one-point tremor is amplified into a standing oscillation.
    func testMeasuringAgainstTheMovingDividerWouldNeverSettle() {
        var transaction = BrowserSplitWidthTransaction(persistedFractions: [0.5, 0.5])
        let grabbed = dividerPosition(of: transaction)
        let pointer = grabbed + 120

        var positions: [CGFloat] = []
        for _ in 0..<layoutPasses {
            // The handle's own space: the pointer's travel, less the travel the
            // handle it is measured against has already made.
            let travelled = dividerPosition(of: transaction) - grabbed
            transaction.resize(
                dividerIndex: 0,
                delta: pointer - grabbed - travelled,
                containerWidth: containerWidth
            )
            positions.append(dividerPosition(of: transaction))
        }

        guard let landed = positions.last else { return XCTFail("No layout passes ran.") }
        XCTAssertGreaterThan(
            Set(positions.map { ($0 * 100).rounded() }).count,
            1,
            """
            Feeding a divider's own position back into the drag that moves it is \
            the loop this fix removes; a version of it that settled would mean \
            the test no longer reproduces it.
            """
        )
        XCTAssertGreaterThan(
            abs(landed - pointer),
            0.5,
            "The loop costs tracking too: the boundary never arrives at the pointer."
        )
    }

    func testAccessibilityStepsMeasureFromTheLayoutOnScreen() {
        var transaction = makeTransaction()
        let step = BrowserSplitCardResizeHandleMetrics.accessibilityStep

        transaction.resize(dividerIndex: 0, delta: step, containerWidth: containerWidth)
        _ = transaction.commit()
        let afterOne = transaction.fractions[0]
        transaction.resize(dividerIndex: 0, delta: step, containerWidth: containerWidth)
        _ = transaction.commit()

        XCTAssertGreaterThan(
            transaction.fractions[0],
            afterOne,
            "Each step commits, so the next one starts from the layout it produced."
        )
    }

    // MARK: - Commit contract

    func testADragMovesTheLiveLayoutBeforeItIsCommitted() {
        var transaction = makeTransaction()

        transaction.resize(dividerIndex: 0, delta: 40, containerWidth: containerWidth)

        XCTAssertGreaterThan(transaction.fractions[0], transaction.persistedFractions[0])
    }

    func testCommittingPublishesTheLayoutTheDragSettledOn() {
        var transaction = makeTransaction()

        transaction.resize(dividerIndex: 0, delta: 40, containerWidth: containerWidth)
        let committed = transaction.commit()

        XCTAssertEqual(committed, transaction.fractions)
        XCTAssertEqual(transaction.persistedFractions, transaction.fractions)
    }

    func testCommittingAnUnchangedLayoutHasNothingToPersist() {
        var transaction = makeTransaction()

        transaction.resize(dividerIndex: 0, delta: 24, containerWidth: containerWidth)
        transaction.resize(dividerIndex: 0, delta: 0, containerWidth: containerWidth)

        XCTAssertNil(
            transaction.commit(),
            "A drag that landed where it started has nothing to persist."
        )
    }

    func testTheNextDragMeasuresFromTheLayoutTheLastOneLeft() {
        var transaction = makeTransaction()

        transaction.resize(dividerIndex: 0, delta: 40, containerWidth: containerWidth)
        _ = transaction.commit()
        let settled = transaction.fractions
        transaction.resize(dividerIndex: 0, delta: 0, containerWidth: containerWidth)

        assertFractions(
            transaction.fractions,
            equal: settled,
            "A fresh drag with no travel yet cannot move the layout."
        )
    }

    func testAdoptingNewFractionsDropsTheDragInFlight() {
        var transaction = makeTransaction()

        transaction.resize(dividerIndex: 0, delta: 24, containerWidth: containerWidth)
        transaction.begin(fractions: [0.5, 0.5])
        transaction.resize(dividerIndex: 0, delta: 0, containerWidth: containerWidth)

        assertFractions(
            transaction.fractions,
            equal: [0.5, 0.5],
            "A membership change replaces the layout the drag was moving."
        )
    }

    // MARK: - Helpers

    private func makeTransaction() -> BrowserSplitWidthTransaction {
        BrowserSplitWidthTransaction(persistedFractions: [0.4, 0.35, 0.25])
    }

    /// Where the row would draw the divider after the first card, which is what
    /// a gesture measured in the handle's own space would resolve against.
    private func dividerPosition(
        of transaction: BrowserSplitWidthTransaction
    ) -> CGFloat {
        BrowserSplitColumnLayout.dividerLeadingDistance(
            after: 0,
            cardWidths: BrowserSplitColumnLayout.widths(
                containerWidth: containerWidth,
                fractions: transaction.fractions
            )
        )
    }

    private func assertFractions(
        _ fractions: [Double],
        equal expected: [Double],
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(fractions.count, expected.count, message, file: file, line: line)
        for (actual, wanted) in zip(fractions, expected) {
            XCTAssertEqual(actual, wanted, accuracy: 1e-9, message, file: file, line: line)
        }
    }
}
