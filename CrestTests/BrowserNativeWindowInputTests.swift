import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserNativeWindowInputTests: XCTestCase {
    func testBrowserChromeDisablesAutomaticTitlebarDraggingWithoutReplacingNativeControls() throws {
        let window = makeWindow()
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let buttons = BrowserNativeWindowControlsPolicy.buttonTypes.compactMap(window.standardWindowButton)
        let input = NSTextField(frame: NSRect(x: 350, y: 560, width: 200, height: 28))
        content.addSubview(input)
        let chrome = BrowserNativeWindowControlsHostView()
        content.addSubview(chrome)
        window.layoutIfNeeded()

        // Automatic titlebar drags are decided before the content receives its
        // mouse-drag sequence. Explicit sidebar window gestures remain separate.
        XCTAssertFalse(window.isMovable)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(content.hitTest(NSPoint(x: 400, y: 574)) === input)
        for (type, button) in zip(BrowserNativeWindowControlsPolicy.buttonTypes, buttons) {
            XCTAssertTrue(window.standardWindowButton(type) === button)
            XCTAssertTrue(button.isEnabled)
        }

        chrome.isVisible = false
        chrome.sidebarOnRight = true
        chrome.applyBrowserChrome()
        XCTAssertFalse(window.isMovable)
        XCTAssertTrue(content.hitTest(NSPoint(x: 400, y: 574)) === input)
    }

    func testDetachingChromeRestoresEachWindowsOriginalDraggingPolicy() throws {
        for originallyMovable in [true, false] {
            let window = makeWindow()
            defer { window.close() }
            window.isMovable = originallyMovable
            let chrome = BrowserNativeWindowControlsHostView()
            try XCTUnwrap(window.contentView).addSubview(chrome)
            XCTAssertFalse(window.isMovable)

            chrome.removeFromSuperview()

            XCTAssertEqual(window.isMovable, originallyMovable)
            chrome.restoreWindowChrome()
            XCTAssertEqual(window.isMovable, originallyMovable)
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
