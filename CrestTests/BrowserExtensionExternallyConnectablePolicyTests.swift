import XCTest

@testable import Crest

final class BrowserExtensionExternallyConnectablePolicyTests: XCTestCase {
    func testBlankDuplicateAndNonStringEntriesAreDropped() {
        let manifest: [String: Any] = [
            "externally_connectable": [
                "matches": [" https://claude.ai/* ", "https://claude.ai/*", "", 7, NSNull()]
            ]
        ]
        XCTAssertEqual(
            BrowserExtensionExternallyConnectablePolicy.matchPatterns(in: manifest),
            ["https://claude.ai/*"]
        )
    }

}
