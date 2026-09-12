import SwiftUI
import XCTest

@testable import Crest

final class BrowserSidebarInteractionPolicyTests: XCTestCase {

    func testInputCapabilitiesChooseConsistentProfilesIncludingTouchWithHover() {
        for hover in [false, true] {
            for touch in [false, true] {
                let input = capabilities(hover: hover, touch: touch)
                XCTAssertEqual(BrowserSidebarInteractionPolicy.trailingControlMetrics(input), touch ? .touch : .pointer)
                XCTAssertEqual(BrowserSidebarInteractionPolicy.tabRowMetrics(input), touch ? .touch : .pointer)
                XCTAssertEqual(BrowserSidebarInteractionPolicy.addressFieldMetrics(input), touch ? .touch : .pointer)
                XCTAssertEqual(
                    BrowserSidebarInteractionPolicy.navigationControlMetrics(input), touch ? .touch : .pointer)
                XCTAssertEqual(BrowserSidebarInteractionPolicy.spaceHeaderMetrics(input), touch ? .touch : .pointer)
                XCTAssertEqual(BrowserSidebarInteractionPolicy.spacePickerMetrics(input), touch ? .touch : .pointer)
                XCTAssertEqual(BrowserSidebarInteractionPolicy.splitGroupRowMetrics(input), touch ? .touch : .pointer)
                XCTAssertEqual(BrowserSidebarInteractionPolicy.newTabRowMetrics(input), touch ? .touch : .pointer)
                XCTAssertEqual(BrowserSidebarInteractionPolicy.tabListMetrics(input), touch ? .touch : .pointer)
            }
        }
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
