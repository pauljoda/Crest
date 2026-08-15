import XCTest
@testable import Crest

final class BrowserUtilityAccessibilityIDTests: XCTestCase {
    func testUtilityIdentifiersDoNotDependOnLocalizedTitles() {
        XCTAssertEqual(
            BrowserUtilityAccessibilityID.list(.archive),
            "archive-utility-list"
        )
        XCTAssertEqual(
            BrowserUtilityAccessibilityID.list(.history),
            "history-utility-list"
        )
        XCTAssertEqual(
            BrowserUtilityAccessibilityID.destination(.downloads),
            "utility-destination-downloads"
        )
    }
}
