import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserShortcutRecorderTests: XCTestCase {
    func testHardwareKeyCodesPreserveTheExistingSpecialKeyMapping() {
        let expected: [(BrowserShortcutHardwareKeyCode, BrowserShortcutSpecialKey)] = [
            (.tab, .tab),
            (.leftArrow, .leftArrow),
            (.rightArrow, .rightArrow),
            (.upArrow, .upArrow),
            (.downArrow, .downArrow),
            (.escape, .escape),
            (.returnKey, .returnKey),
            (.keypadEnter, .returnKey),
            (.delete, .delete),
            (.forwardDelete, .forwardDelete),
            (.home, .home),
            (.end, .end),
            (.pageUp, .pageUp),
            (.pageDown, .pageDown),
            (.space, .space),
            (.f1, .f1),
            (.f2, .f2),
            (.f3, .f3),
            (.f4, .f4),
            (.f5, .f5),
            (.f6, .f6),
            (.f7, .f7),
            (.f8, .f8),
            (.f9, .f9),
            (.f10, .f10),
            (.f11, .f11),
            (.f12, .f12),
            (.f13, .f13),
            (.f14, .f14),
            (.f15, .f15),
            (.f16, .f16),
            (.f17, .f17),
            (.f18, .f18),
            (.f19, .f19),
            (.f20, .f20),
        ]

        XCTAssertEqual(BrowserShortcutHardwareKeyCode.allCases.count, expected.count)
        for (keyCode, specialKey) in expected {
            XCTAssertEqual(
                BrowserShortcutSpecialKey(keyCode: keyCode.rawValue),
                specialKey
            )
        }
    }

    func testEndingARecordingRemovesTheLocalEventMonitor() {
        let button = ShortcutRecorderButton()
        button.restingTitle = "⌘T"

        button.beginRecording()

        XCTAssertTrue(button.isRecording)
        XCTAssertTrue(button.hasActiveEventMonitor)
        XCTAssertEqual(button.title, "Type Shortcut")

        button.endRecording()

        XCTAssertFalse(button.isRecording)
        XCTAssertFalse(button.hasActiveEventMonitor)
        XCTAssertEqual(button.title, "⌘T")
    }

    func testResigningFirstResponderEndsRecordingAndRestoresPresentation() {
        let button = ShortcutRecorderButton()
        button.restingTitle = "⌥G"
        button.beginRecording()

        XCTAssertTrue(button.resignFirstResponder())

        XCTAssertFalse(button.isRecording)
        XCTAssertFalse(button.hasActiveEventMonitor)
        XCTAssertEqual(button.title, "⌥G")
        XCTAssertNil(button.bezelColor)
    }
}
