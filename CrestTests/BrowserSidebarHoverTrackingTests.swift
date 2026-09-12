import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarHoverTrackingTests: XCTestCase {

    func testTrackingDoesNotClaimClicksOrDrags() throws {
        let fixture = Fixture()
        fixture.view.updateTrackingAreas()
        let area = try XCTUnwrap(fixture.view.trackingAreas.first)
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
        XCTAssertTrue(area.options.contains(.activeInKeyWindow))
        XCTAssertTrue(area.options.contains(.inVisibleRect))
        XCTAssertNil(fixture.view.hitTest(CGPoint(x: 90, y: 100)))
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
