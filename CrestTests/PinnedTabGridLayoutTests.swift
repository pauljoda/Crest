import XCTest

@testable import Crest

final class PinnedTabGridLayoutTests: XCTestCase {
    func testPinnedTabsUseTheSameResidencyAppearanceAsOtherTabs() {
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.tabResidencySaturation(
                isLoaded: true
            ),
            1
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.tabResidencyOpacity(
                isLoaded: true
            ),
            1
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.tabResidencySaturation(
                isLoaded: false
            ),
            0.3
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.tabResidencyOpacity(
                isLoaded: false
            ),
            0.5
        )
    }

    func testGridUsesEveryAvailableColumnForOneThroughFourPins() {
        XCTAssertEqual(PinnedTabGridLayout.columnCount(for: 1), 1)
        XCTAssertEqual(PinnedTabGridLayout.columnCount(for: 2), 2)
        XCTAssertEqual(PinnedTabGridLayout.columnCount(for: 3), 3)
        XCTAssertEqual(PinnedTabGridLayout.columnCount(for: 4), 4)
    }

    func testGridBalancesArcStyleRowsForFiveThroughTwelvePins() {
        let expectedColumns = [
            5: 3,
            6: 3,
            7: 4,
            8: 4,
            9: 3,
            10: 4,
            11: 4,
            12: 4,
        ]

        for (count, columns) in expectedColumns {
            XCTAssertEqual(PinnedTabGridLayout.columnCount(for: count), columns, "count: \(count)")
        }
    }
}
