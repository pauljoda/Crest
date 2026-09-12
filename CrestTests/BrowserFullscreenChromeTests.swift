import AppKit
import XCTest

@testable import Crest

final class BrowserFullscreenChromeTests: XCTestCase {

    @MainActor
    func testCollapsedSidebarHoverTrackingUsesAppKitWithoutClaimingInput() {
        var hoverChanges: [Bool] = []
        let view = BrowserCollapsedSidebarHoverTrackingView {
            hoverChanges.append($0)
        }
        view.frame = CGRect(x: 0, y: 0, width: 14, height: 640)

        view.updateTrackingAreas()

        let trackingArea = try? XCTUnwrap(view.trackingAreas.first)
        XCTAssertNotNil(trackingArea)
        XCTAssertTrue(
            trackingArea?.options.contains(.mouseEnteredAndExited) == true
        )
        XCTAssertTrue(trackingArea?.options.contains(.activeInKeyWindow) == true)
        XCTAssertTrue(trackingArea?.options.contains(.inVisibleRect) == true)
        XCTAssertNil(view.hitTest(CGPoint(x: 7, y: 320)))

        view.reportHover(true)
        view.reportHover(false)

        XCTAssertEqual(hoverChanges, [true, false])
    }
}
