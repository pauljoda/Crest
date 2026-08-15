import Foundation
import XCTest

@testable import Crest

/// Which fractions a split starts a layout pass with.
///
/// The window model and the columns view both ask this, and a disagreement
/// between them is either a crash — a view indexing a fraction list shorter
/// than its members — or a layout drawn from numbers written for a group that
/// no longer exists.
final class BrowserSplitLayoutSeedPolicyTests: XCTestCase {
    func testAStoredLayoutForThisManyMembersIsAdopted() {
        let fractions = BrowserSplitLayoutSeedPolicy.fractions(
            persisted: [0.6, 0.4],
            memberCount: 2
        )

        XCTAssertEqual(fractions.count, 2)
        XCTAssertEqual(fractions[0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(fractions[1], 0.4, accuracy: 0.0001)
    }

    func testAStoredLayoutIsNormalizedBeforeItIsAdopted() {
        let fractions = BrowserSplitLayoutSeedPolicy.fractions(
            persisted: [3, 1],
            memberCount: 2
        )

        XCTAssertEqual(fractions.reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertEqual(fractions[0], 0.75, accuracy: 0.0001)
    }

    func testNoStoredLayoutStartsAsEqualColumns() {
        let fractions = BrowserSplitLayoutSeedPolicy.fractions(
            persisted: nil,
            memberCount: 3
        )

        XCTAssertEqual(fractions.count, 3)
        for fraction in fractions {
            XCTAssertEqual(fraction, 1.0 / 3.0, accuracy: 0.0001)
        }
    }

    /// A group of three has no honest reading of two fractions, so the stale
    /// list is discarded rather than padded or truncated.
    func testAStoredLayoutFromAnotherMemberCountIsDiscarded() {
        let grown = BrowserSplitLayoutSeedPolicy.fractions(
            persisted: [0.7, 0.3],
            memberCount: 3
        )
        let shrunk = BrowserSplitLayoutSeedPolicy.fractions(
            persisted: [0.5, 0.3, 0.2],
            memberCount: 2
        )

        XCTAssertEqual(grown, BrowserSplitColumnLayout.equalFractions(count: 3))
        XCTAssertEqual(shrunk, BrowserSplitColumnLayout.equalFractions(count: 2))
    }

    func testASingleMemberIsAWholeColumn() {
        XCTAssertEqual(
            BrowserSplitLayoutSeedPolicy.fractions(persisted: nil, memberCount: 1),
            [1]
        )
    }

    func testNoMembersHaveNoColumns() {
        XCTAssertEqual(
            BrowserSplitLayoutSeedPolicy.fractions(
                persisted: [0.5, 0.5],
                memberCount: 0
            ),
            []
        )
    }
}
