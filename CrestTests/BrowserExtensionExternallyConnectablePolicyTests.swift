import XCTest

@testable import Crest

final class BrowserExtensionExternallyConnectablePolicyTests: XCTestCase {
    func testPatternsAreReadInAuthoredOrder() {
        let manifest: [String: Any] = [
            "externally_connectable": [
                "matches": ["https://claude.ai/*", "https://*.claude.ai/*"]
            ]
        ]
        XCTAssertEqual(
            BrowserExtensionExternallyConnectablePolicy.matchPatterns(in: manifest),
            ["https://claude.ai/*", "https://*.claude.ai/*"]
        )
    }

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

    func testAManifestWithoutTheSectionOrWithAMalformedOneHasNoPatterns() {
        XCTAssertEqual(
            BrowserExtensionExternallyConnectablePolicy.matchPatterns(in: ["name": "Probe"]),
            []
        )
        XCTAssertEqual(
            BrowserExtensionExternallyConnectablePolicy.matchPatterns(
                in: ["externally_connectable": ["ids": ["abc"]]]
            ),
            []
        )
        XCTAssertEqual(
            BrowserExtensionExternallyConnectablePolicy.matchPatterns(
                in: ["externally_connectable": ["matches": "https://claude.ai/*"]]
            ),
            []
        )
    }
}
