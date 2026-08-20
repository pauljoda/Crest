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
        XCTAssertEqual(metrics.restingCloseOpacity, 1)
        XCTAssertTrue(metrics.usesChromeControlStyle)
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
        XCTAssertEqual(metrics.restingCloseOpacity, 0.65)
        XCTAssertFalse(metrics.usesChromeControlStyle)
    }

    // MARK: - Revealing and dimming the trailing control

    /// A pointer row hides its control at rest and shows it once the row can
    /// say something about itself: the pointer is over it, or it is the
    /// selected row. A touch row cannot hide anything, so every combination
    /// answers the same way.
    func testRevealMatrixFollowsTheShellRatherThanTheRow() {
        let pointer = BrowserTabTrailingControlMetrics.pointer
        XCTAssertFalse(pointer.isRevealed(isHovering: false, isSelected: false))
        XCTAssertTrue(pointer.isRevealed(isHovering: true, isSelected: false))
        XCTAssertTrue(pointer.isRevealed(isHovering: false, isSelected: true))

        let touch = BrowserTabTrailingControlMetrics.touch
        XCTAssertTrue(touch.isRevealed(isHovering: false, isSelected: false))
        XCTAssertTrue(touch.isRevealed(isHovering: true, isSelected: false))
        XCTAssertTrue(touch.isRevealed(isHovering: false, isSelected: true))
    }

    /// The exact opacities each shell draws a revealed close control at. A
    /// pointer control has already been asked for by the time it appears, so
    /// it never rests dim; a touch control is on every row at once and holds
    /// the unselected ones back.
    func testOnlyAnAlwaysVisibleCloseControlDimsOnAnUnselectedRow() {
        XCTAssertEqual(
            BrowserTabTrailingControlMetrics.pointer.closeOpacity(isSelected: false),
            1
        )
        XCTAssertEqual(
            BrowserTabTrailingControlMetrics.pointer.closeOpacity(isSelected: true),
            1
        )
        XCTAssertEqual(
            BrowserTabTrailingControlMetrics.touch.closeOpacity(isSelected: false),
            0.65
        )
        XCTAssertEqual(
            BrowserTabTrailingControlMetrics.touch.closeOpacity(isSelected: true),
            1
        )
    }

    // MARK: - Row layout

    /// Pins the geometry each shell's rows draw today, so a change to either
    /// profile fails here rather than quietly shifting every title in the
    /// sidebar by a couple of points.
    func testRowLayoutFollowsTheLeastPreciseInputTheShellAccepts() {
        let pointer = BrowserSidebarInteractionPolicy.tabRowMetrics(
            capabilities(hover: true, touch: false)
        )
        XCTAssertEqual(pointer, .pointer)
        XCTAssertEqual(pointer.contentSpacing, 0)
        XCTAssertEqual(pointer.contentLeadingInset, 9)
        XCTAssertEqual(pointer.contentTrailingInset, 9)
        XCTAssertEqual(pointer.surfaceHorizontalInset, 8)
        XCTAssertNil(pointer.faviconSlot)
        XCTAssertTrue(pointer.fillsRowHeight)

        let touch = BrowserSidebarInteractionPolicy.tabRowMetrics(
            capabilities(hover: false, touch: true)
        )
        XCTAssertEqual(touch, .touch)
        XCTAssertEqual(touch.contentSpacing, 4)
        XCTAssertEqual(touch.contentLeadingInset, 12)
        XCTAssertEqual(touch.contentTrailingInset, 4)
        XCTAssertEqual(touch.surfaceHorizontalInset, 8)
        XCTAssertEqual(
            touch.faviconSlot,
            BrowserSidebarTabFaviconSlot(width: 20, glyphSize: 17, glyphWeight: .medium)
        )
        XCTAssertFalse(touch.fillsRowHeight)
    }

    /// A trackpad beside a touchscreen must not tighten the row back down.
    func testAddingHoverToATouchShellKeepsTheTouchRowLayout() {
        XCTAssertEqual(
            BrowserSidebarInteractionPolicy.tabRowMetrics(
                capabilities(hover: true, touch: true)
            ),
            BrowserSidebarInteractionPolicy.tabRowMetrics(
                capabilities(hover: false, touch: true)
            )
        )
    }

    // MARK: - Promotion anchoring

    /// The two anchors are alternatives, not a pair: a shell that zooms the
    /// page in with the system's own transition registers the row there, and
    /// a matched-geometry destination under the same identity would be a
    /// second answer to the same question.
    func testOnlyAShellWithoutTheNativeZoomAnchorsWithMatchedGeometry() {
        XCTAssertTrue(
            BrowserSidebarInteractionPolicy.usesMatchedGeometryPromotionDestination(
                BrowserInteractionCapabilities()
            )
        )
        XCTAssertFalse(
            BrowserSidebarInteractionPolicy.usesMatchedGeometryPromotionDestination(
                BrowserInteractionCapabilities(usesNativeNavigationTransition: true)
            )
        )
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
