import XCTest

@testable import Crest

/// Open Next Extension steps through each extension once and always reaches
/// the press that closes the popup, whatever the pin list and the page report.
final class BrowserExtensionPopupCycleTests: XCTestCase {
    // MARK: - Actions - Stepping

    func testPressesOpenThePinnedThenTheOthersThenClose() {
        let cycle = BrowserExtensionPopupCycle(pinned: ["bravo", "alpha"], others: ["delta"])
        XCTAssertEqual(cycle.step(showing: nil), .open("bravo"))
        XCTAssertEqual(cycle.step(showing: "bravo"), .open("alpha"))
        XCTAssertEqual(cycle.step(showing: "alpha"), .open("delta"))
        XCTAssertEqual(cycle.step(showing: "delta"), .close)
    }

    /// The pin list and the page can both name an extension, as while the
    /// engine's toolbar model has yet to count a pin. It comes once, at its
    /// pinned place, so the presses still reach the close.
    func testAnExtensionNamedTwiceComesOnceSoThePressesStillClose() {
        let cycle = BrowserExtensionPopupCycle(pinned: ["alpha", "bravo"], others: ["alpha", "charlie", "bravo"])
        XCTAssertEqual(cycle.ids, ["alpha", "bravo", "charlie"])
        var shown: String?
        var opened: [String] = []
        while case .open(let next) = cycle.step(showing: shown) {
            opened.append(next)
            shown = next
            if opened.count > cycle.ids.count { break }
        }
        XCTAssertEqual(opened, ["alpha", "bravo", "charlie"])
        XCTAssertEqual(cycle.step(showing: shown), .close)
    }

    func testAPopupOutsideTheCycleStartsItOver() {
        let cycle = BrowserExtensionPopupCycle(pinned: ["alpha"], others: ["bravo"])
        XCTAssertEqual(cycle.step(showing: "opened-by-itself"), .open("alpha"))
    }

    func testNothingToOpenTakesNoStep() {
        XCTAssertNil(BrowserExtensionPopupCycle(pinned: [], others: []).step(showing: nil))
    }
}
