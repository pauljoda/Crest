import SwiftUI
import XCTest

@testable import Crest

final class BrowserSidebarInteractionPolicyTests: XCTestCase {

    // MARK: - Hiding a control until the pointer arrives

    /// The full matrix, because the rule is a conjunction and only one of the
    /// four combinations may hide anything. The touch-and-hover corner is the
    /// one that matters: an iPad with a trackpad reports both, and treating
    /// hover as sufficient there would leave the close control unreachable for
    /// the finger that is still the primary input.
    func testControlsHideUntilHoverOnlyWhereHoverExistsAndTouchDoesNot() {
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(
                capabilities(hover: true, touch: false)
            )
        )
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(
                capabilities(hover: true, touch: true)
            )
        )
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(
                capabilities(hover: false, touch: true)
            )
        )
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(
                capabilities(hover: false, touch: false)
            )
        )
    }

    // MARK: - Trailing control metrics

    /// Pins the numbers the macOS sidebar rows draw today. The hit target is
    /// asserted against both the literal and the token so a change to either
    /// one alone fails here rather than silently resizing every row.
    func testPointerMetricsMatchTheWindowedSidebarRow() {
        let metrics = BrowserSidebarInteractionPolicy.trailingControlMetrics(
            capabilities(hover: true, touch: false)
        )

        XCTAssertEqual(metrics.controlSize, CGSize(width: 28, height: 28))
        XCTAssertEqual(metrics.controlSize.width, CrestLayout.minimumHitTarget)
        XCTAssertEqual(metrics.glyphSize, 12)
        XCTAssertEqual(metrics.glyphWeight, .regular)
        XCTAssertFalse(metrics.isAlwaysVisible)
    }

    /// Pins the numbers the compact sidebar rows draw today. They are literals
    /// rather than tokens on purpose: this suite is hosted on macOS, where the
    /// platform hit target is 28, and the touch profile still has to be 44.
    func testTouchMetricsMatchTheCompactSidebarRow() {
        let metrics = BrowserSidebarInteractionPolicy.trailingControlMetrics(
            capabilities(hover: false, touch: true)
        )

        XCTAssertEqual(metrics.controlSize, CGSize(width: 44, height: 44))
        XCTAssertEqual(metrics.glyphSize, 14)
        XCTAssertEqual(metrics.glyphWeight, .medium)
        XCTAssertTrue(metrics.isAlwaysVisible)
    }

    /// A trackpad beside a touchscreen must not shrink the target back down.
    func testAddingHoverToATouchShellKeepsTheTouchControl() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.trailingControlMetrics(
                capabilities(hover: true, touch: true)
            ),
            BrowserSidebarInteractionPolicy.trailingControlMetrics(
                capabilities(hover: false, touch: true)
            )
        )
    }

    // MARK: - Row height

    func testRowsRestAtTheSidebarRowHeightOnEveryShell() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: true, touch: false),
                dynamicTypeSize: .large
            ),
            CrestLayout.sidebarRowHeight
        )
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: false, touch: true),
                dynamicTypeSize: .large
            ),
            CrestLayout.sidebarRowHeight
        )
    }

    /// The bump is keyed on touch rather than on the text size alone, which is
    /// what keeps the windowed sidebar's rows at one exact height no matter
    /// how large the reader's text is.
    func testOnlyATouchShellGrowsItsRowsAtAnAccessibilityTextSize() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: false, touch: true),
                dynamicTypeSize: .accessibility1
            ),
            56
        )
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.rowMinHeight(
                capabilities(hover: true, touch: false),
                dynamicTypeSize: .accessibility5
            ),
            CrestLayout.sidebarRowHeight
        )
    }

    // MARK: - Split group members

    func testOnlyATouchShellKeepsSplitMembersAtFullRowHeight() {
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.splitMembersUseFullRowHeight(
                capabilities(hover: false, touch: true)
            )
        )
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.splitMembersUseFullRowHeight(
                capabilities(hover: true, touch: true)
            )
        )
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.splitMembersUseFullRowHeight(
                capabilities(hover: true, touch: false)
            )
        )
    }

    // MARK: - Fixtures

    private func capabilities(
        hover: Bool,
        touch: Bool
    ) -> BrowserInteractionCapabilities {
        BrowserInteractionCapabilities(
            supportsHover: hover,
            supportsTouch: touch
        )
    }
}
