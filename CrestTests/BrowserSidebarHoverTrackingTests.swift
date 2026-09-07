import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarHoverTrackingTests: XCTestCase {
    func testMenuDismissedInsideKeepsSidebarOpenWithoutAnotherMouseEvent() {
        let fixture = Fixture()
        let menu = NSMenu()
        fixture.begin(menu)
        fixture.pointer = CGPoint(x: 430, y: 280)
        fixture.view.mouseExited(with: NSEvent())
        XCTAssertEqual(fixture.hoverChanges, [true])

        fixture.pointer = CGPoint(x: 90, y: 500)
        fixture.end(menu)

        XCTAssertEqual(fixture.hoverChanges, [true])
        // AppKit can deliver the old exit after menu tracking ends.
        fixture.view.mouseExited(with: NSEvent())
        XCTAssertEqual(fixture.hoverChanges, [true])

        fixture.pointer = CGPoint(x: 310, y: 500)
        fixture.view.mouseExited(with: NSEvent())
        XCTAssertEqual(fixture.hoverChanges, [true, false])
    }

    func testMenuDismissedOutsideHidesWithoutAnotherMouseEvent() {
        let fixture = Fixture()
        let menu = NSMenu()
        fixture.begin(menu)
        fixture.pointer = CGPoint(x: 430, y: 280)
        XCTAssertEqual(fixture.view.frame.width, 294)
        XCTAssertFalse(
            fixture.view.visibleRect.contains(fixture.view.convert(fixture.pointer, from: nil)),
            "Frame: \(fixture.view.frame), visible: \(fixture.view.visibleRect)"
        )
        fixture.end(menu)
        XCTAssertEqual(fixture.hoverChanges, [true, false])
    }

    func testNestedMenusHoldUntilEveryTrackedMenuCloses() {
        let fixture = Fixture()
        let parent = NSMenu()
        let child = NSMenu()
        fixture.begin(parent)
        fixture.pointer = CGPoint(x: 430, y: 280)
        fixture.begin(child)
        fixture.end(child)
        XCTAssertEqual(fixture.hoverChanges, [true])
        fixture.pointer = CGPoint(x: 1, y: 500)
        fixture.end(parent)
        XCTAssertEqual(fixture.hoverChanges, [true])
    }

    func testRepeatedMenusResampleBothEdgesOfTheFullHoverRegion() {
        let fixture = Fixture()
        for x: CGFloat in [1, 293, 90] {
            fixture.pointer = CGPoint(x: 90, y: 100)
            fixture.view.refreshPointerHover()
            let menu = NSMenu()
            fixture.begin(menu)
            fixture.pointer = CGPoint(x: x, y: 500)
            fixture.end(menu)
            XCTAssertEqual(fixture.hoverChanges.last, true)
            fixture.pointer = CGPoint(x: 295, y: 500)
            fixture.view.mouseExited(with: NSEvent())
            XCTAssertEqual(fixture.hoverChanges.last, false)
        }
        XCTAssertEqual(fixture.hoverChanges, [true, false, true, false, true, false])
    }

    func testMenuOutsideSidebarDoesNotHoldItOpen() {
        let fixture = Fixture()
        fixture.pointer = CGPoint(x: 430, y: 280)
        let menu = NSMenu()
        fixture.begin(menu)
        fixture.view.mouseExited(with: NSEvent())
        XCTAssertEqual(fixture.hoverChanges, [true, false])
        fixture.end(menu)
        XCTAssertEqual(fixture.hoverChanges, [true, false])
    }

    func testDisabledOrDetachedTrackerCannotKeepAStaleMenuHold() {
        let fixture = Fixture()
        let menu = NSMenu()
        fixture.begin(menu)
        fixture.view.isEnabled = false
        fixture.pointer = CGPoint(x: 430, y: 280)
        fixture.end(menu)
        XCTAssertEqual(fixture.hoverChanges, [true])
        fixture.view.isEnabled = true
        fixture.view.refreshPointerHover()
        XCTAssertEqual(fixture.hoverChanges, [true])
        fixture.pointer = CGPoint(x: 90, y: 100)
        fixture.view.refreshPointerHover()
        fixture.pointer = CGPoint(x: 430, y: 280)
        fixture.view.refreshPointerHover()
        XCTAssertEqual(fixture.hoverChanges.last, false)

        fixture.view.removeFromSuperview()
        fixture.pointer = CGPoint(x: 90, y: 100)
        fixture.begin(menu)
        fixture.end(menu)
        XCTAssertEqual(fixture.hoverChanges.last, false)
    }

    func testTrackingDoesNotClaimClicksOrDrags() throws {
        let fixture = Fixture()
        fixture.view.updateTrackingAreas()
        let area = try XCTUnwrap(fixture.view.trackingAreas.first)
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
        XCTAssertTrue(area.options.contains(.activeInKeyWindow))
        XCTAssertTrue(area.options.contains(.inVisibleRect))
        XCTAssertNil(fixture.view.hitTest(CGPoint(x: 90, y: 100)))
    }

    func testOffscreenGeometryAtRevealIsNotReportedAsAnExit() {
        let fixture = Fixture(pointer: CGPoint(x: 430, y: 280))
        XCTAssertTrue(fixture.hoverChanges.isEmpty)
        fixture.pointer = CGPoint(x: 90, y: 100)
        fixture.view.refreshPointerHover()
        XCTAssertEqual(fixture.hoverChanges, [true])
        fixture.pointer = CGPoint(x: 430, y: 280)
        fixture.view.refreshPointerHover()
        XCTAssertEqual(fixture.hoverChanges, [true, false])
    }

    @MainActor
    private final class Fixture {
        let center = NotificationCenter()
        let window = KeyWindow(
            contentRect: CGRect(x: 170, y: 120, width: 1000, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        var pointer = CGPoint(x: 90, y: 100)
        var hoverChanges: [Bool] = []
        lazy var view = BrowserSidebarHoverTrackingView(
            notificationCenter: center,
            pointerLocation: { [weak self] in
                guard let self else { return .zero }
                return window.convertPoint(toScreen: pointer)
            },
            onHoverChange: { [weak self] in self?.hoverChanges.append($0) }
        )

        init(pointer: CGPoint = CGPoint(x: 90, y: 100)) {
            self.pointer = pointer
            window.isReleasedWhenClosed = false
            view.frame = CGRect(x: 0, y: 0, width: 294, height: 640)
            window.contentView?.addSubview(view)
            view.refreshPointerHover()
        }

        func begin(_ menu: NSMenu) {
            center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        }

        func end(_ menu: NSMenu) {
            center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        }
    }

    private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }
}
