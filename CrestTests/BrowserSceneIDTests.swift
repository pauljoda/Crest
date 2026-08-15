import XCTest
@testable import Crest

final class BrowserSceneIDTests: XCTestCase {
    func testSceneIdentifiersAreStableAndUnique() {
        XCTAssertEqual(BrowserSceneID.browser.rawValue, "browser")
        XCTAssertEqual(BrowserSceneID.quickWindow.rawValue, "quick-window")
        XCTAssertEqual(BrowserSceneID.privateBrowser.rawValue, "private-browser")
        XCTAssertEqual(BrowserSceneID.settings.rawValue, "settings")
        XCTAssertEqual(
            Set(BrowserSceneID.allCases.map(\.rawValue)).count,
            BrowserSceneID.allCases.count
        )
    }
}
