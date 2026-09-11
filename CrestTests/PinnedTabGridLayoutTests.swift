import XCTest

@testable import Crest

final class PinnedTabGridLayoutTests: XCTestCase {
    func testCustomizedPinsKeepTargetsAndDragGapInsideNarrowGrid() throws {
        let ids = (0..<8).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        for width in [CGFloat(176), 260, 356] {
            var layout = BrowserPinnedTabReorderLayout(ids: ids)
            layout.availableWidth = width
            layout.preferredColumns = 6
            layout.tileHeight = 64
            layout.minimumTileWidth = 44
            layout.tileSpacing = 14
            layout.liftedID = ids[0]
            layout.insertionIndex = 3
            let bounds = CGRect(x: 12, y: 24, width: width, height: layout.height)
            var previous: CGRect?
            for slot in layout.slots {
                let frame = try XCTUnwrap(layout.frame(for: slot, in: bounds))
                XCTAssertGreaterThanOrEqual(frame.width, 44)
                XCTAssertEqual(frame.height, 64)
                XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX)
                XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX + 0.001)
                XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY)
                if let previous { XCTAssertFalse(previous.intersects(frame)) }
                previous = frame
            }
            XCTAssertNotNil(layout.frame(for: .gap, in: bounds))
            XCTAssertNil(layout.frame(for: .tab(ids[0]), in: bounds))
        }
        XCTAssertEqual(BrowserSidebarDensityPolicy.rowHeight(base: 38, scale: 0.7, touch: true), 44)
        XCTAssertEqual(BrowserSidebarDensityPolicy.rowHeight(base: 38, scale: 0.7, touch: false), 26.6, accuracy: 0.01)
        XCTAssertGreaterThan(BrowserSidebarDensityPolicy.rowSeparation(scale: 0.7), 0)
        XCTAssertEqual(BrowserSidebarDensityPolicy.rowSeparation(scale: 1), 0)

    }

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

    func testScaledPinsBalanceRowsAndPreserveProportions() throws {
        let ids = (0..<9).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        for (scale, expectedColumns) in [(1.0, 3), (0.9, 3), (0.7, 5)] {
            var layout = BrowserPinnedTabReorderLayout(ids: ids, availableWidth: 264, tabScale: scale)
            layout.tileHeight = BrowserSidebarDensityPolicy.pinHeight(scale: scale)
            layout.tileSpacing = BrowserSidebarDensityPolicy.pinSpacing(scale: scale)
            layout.minimumTileWidth = BrowserSidebarDensityPolicy.pinMinimumWidth(scale: scale)
            XCTAssertEqual(layout.columns, expectedColumns)
            let bounds = CGRect(x: 8, y: 20, width: layout.availableWidth, height: layout.height)
            let first = try XCTUnwrap(layout.frame(for: .tab(ids[0]), in: bounds))
            let last = try XCTUnwrap(layout.frame(for: .tab(ids[layout.columns - 1]), in: bounds))
            XCTAssertEqual(first.minX, bounds.minX)
            XCTAssertEqual(last.maxX, bounds.maxX, accuracy: 0.001)
            XCTAssertEqual(first.height, 47 * scale, accuracy: 0.001)
            XCTAssertEqual(
                layout.height,
                scale < 0.9
                    ? 2 * layout.tileHeight + layout.tileSpacing : 3 * layout.tileHeight + 2 * layout.tileSpacing)
            layout.preferredColumns = 2
            XCTAssertEqual(layout.columns, 2)
        }
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
            let ids = (0..<count).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
            XCTAssertEqual(BrowserPinnedTabReorderLayout(ids: ids).columns, columns, "count: \(count)")
        }
    }
}
