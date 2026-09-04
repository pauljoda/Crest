import Foundation
import XCTest

@testable import Crest

final class BrowserExtensionTabIdentityTests: XCTestCase {
    func testRootURLsMatchWithOrWithoutTheTrailingSlash() {
        XCTAssertTrue(
            BrowserExtensionTabIdentity.urlMatches(reported: "https://apple.com/", state: URL(string: "https://apple.com")))
        XCTAssertTrue(
            BrowserExtensionTabIdentity.urlMatches(reported: "https://apple.com", state: URL(string: "https://apple.com/")))
    }

    func testSchemeAndHostCaseDoNotMatterButPathsAndQueriesDo() {
        XCTAssertTrue(
            BrowserExtensionTabIdentity.urlMatches(
                reported: "HTTPS://Developer.Apple.com/xcode/", state: URL(string: "https://developer.apple.com/xcode/")))
        XCTAssertFalse(
            BrowserExtensionTabIdentity.urlMatches(
                reported: "https://developer.apple.com/xcode", state: URL(string: "https://developer.apple.com/xcode/swiftui")))
        XCTAssertFalse(
            BrowserExtensionTabIdentity.urlMatches(
                reported: "https://example.com/?a=1", state: URL(string: "https://example.com/?a=2")))
    }

    func testAnUnreportedURLMatchesAnyTabAndAMissingStateURLMatchesNone() {
        XCTAssertTrue(BrowserExtensionTabIdentity.urlMatches(reported: nil, state: nil))
        XCTAssertFalse(BrowserExtensionTabIdentity.urlMatches(reported: "https://apple.com/", state: nil))
    }
}
