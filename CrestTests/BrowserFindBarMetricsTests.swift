import SwiftUI
import XCTest

@testable import Crest

final class BrowserFindBarMetricsTests: XCTestCase {

    // MARK: - Choosing the profile

    /// Touch decides the find bar the way it decides the sidebar's rows, and
    /// nothing else does. The hover-and-touch corner is the one that matters:
    /// an iPad with a trackpad attached still has to give a finger a 44pt
    /// chevron.
    func testTouchAloneDecidesWhichProfileTheBarDrawsWith() {
        XCTAssertEqual(
            BrowserFindBarMetrics.resolve(
                capabilities(hover: true, touch: false)
            ),
            .pointer
        )
        XCTAssertEqual(
            BrowserFindBarMetrics.resolve(
                capabilities(hover: false, touch: false)
            ),
            .pointer
        )
        XCTAssertEqual(
            BrowserFindBarMetrics.resolve(
                capabilities(hover: true, touch: true)
            ),
            .touch
        )
        XCTAssertEqual(
            BrowserFindBarMetrics.resolve(
                capabilities(hover: false, touch: true)
            ),
            .touch
        )
    }

    // MARK: - The drawn profiles

    /// Pins the numbers the windowed find panel drew before the two forks
    /// became one bar.
    func testPointerProfileMatchesTheWindowedFindPanel() {
        let metrics = BrowserFindBarMetrics.pointer

        XCTAssertEqual(metrics.itemSpacing, 6)
        XCTAssertEqual(metrics.leadingPadding, 10)
        XCTAssertEqual(metrics.trailingPadding, 10)
        XCTAssertEqual(metrics.queryWidth, 190)
        XCTAssertEqual(metrics.barHeight, 36)
        XCTAssertFalse(metrics.growsWithContent)
        XCTAssertNil(metrics.controlSize)
        XCTAssertEqual(metrics.matchStatusStyle, .label)
        XCTAssertEqual(metrics.matchStatusWidth, 62)
    }

    /// Pins the numbers the compact find bar drew before the merge. They are
    /// literals rather than tokens on purpose: this suite is hosted on macOS,
    /// where `CrestLayout.minimumHitTarget` resolves to the pointer shell's 28,
    /// and a touch control still has to be 44.
    func testTouchProfileMatchesTheCompactFindBar() {
        let metrics = BrowserFindBarMetrics.touch

        XCTAssertEqual(metrics.itemSpacing, 6)
        XCTAssertEqual(metrics.leadingPadding, 14)
        XCTAssertEqual(metrics.trailingPadding, 4)
        XCTAssertNil(metrics.queryWidth)
        XCTAssertEqual(metrics.barHeight, 44)
        XCTAssertTrue(metrics.growsWithContent)
        XCTAssertEqual(metrics.controlSize, CGSize(width: 40, height: 44))
        XCTAssertEqual(metrics.matchStatusStyle, .symbol)
        XCTAssertEqual(metrics.matchStatusWidth, 24)
    }

    /// The lift under the bar was already identical in both forks, so it is one
    /// value rather than a field either profile can drift on.
    func testBothShellsLiftTheBarIdentically() {
        XCTAssertEqual(BrowserFindBarMetrics.shadowOpacity, 0.14)
        XCTAssertEqual(BrowserFindBarMetrics.shadowRadius, 12)
        XCTAssertEqual(BrowserFindBarMetrics.shadowOffset, 5)
    }

    // MARK: - What the bar says about the search

    /// The symbol spelling carries the same words as the label spelling, which
    /// is what lets one component serve both: the shared state already owns
    /// every string either shell reads out.
    func testEveryReportedStateCarriesTheWordsBothSpellingsUse() {
        XCTAssertNil(BrowserFindMatchState.idle.accessibilityLabel)
        XCTAssertEqual(
            BrowserFindMatchState.searching.accessibilityLabel,
            "Searching"
        )
        XCTAssertEqual(
            BrowserFindMatchState.found.accessibilityLabel,
            "Match found"
        )
        XCTAssertEqual(
            BrowserFindMatchState.notFound.accessibilityLabel,
            "No match"
        )
    }

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
