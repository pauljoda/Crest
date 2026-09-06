import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionPopupToggleTests: XCTestCase {
    func testDismissalConsumesOnlyTheInvokingPress() {
        var state = BrowserExtensionPopupToggleState<String>()
        state.beganMouseDown(at: 1)
        state.dismissed("dark-reader", at: 1)
        XCTAssertTrue(state.consume("dark-reader"))
        XCTAssertFalse(state.consume("dark-reader"))
    }

    func testLaterClickCanReopenImmediately() {
        var state = BrowserExtensionPopupToggleState<String>()
        state.dismissed("dark-reader", at: 1)
        state.beganMouseDown(at: 1.01)
        XCTAssertFalse(state.consume("dark-reader"))
    }

    func testDismissalDoesNotConsumeAnotherExtensionAction() {
        var state = BrowserExtensionPopupToggleState<String>()
        state.dismissed("dark-reader", at: 1)
        XCTAssertFalse(state.consume("ublock"))
    }

    func testAppKitDismissalBeforeLocalMonitorKeepsSamePress() {
        var state = BrowserExtensionPopupToggleState<String>()
        state.dismissed("dark-reader", at: 1)
        state.beganMouseDown(at: 1)
        XCTAssertTrue(state.consume("dark-reader"))
    }

}
