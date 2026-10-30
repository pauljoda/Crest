import Foundation
import XCTest

@testable import Crest

/// What Tidy's on-device model reads about a tab is its title, host and path:
/// never the query or fragment, which can carry tokens and personal details.
final class BrowserTidyPrivacyTests: XCTestCase {
    func testTidyModelReadsTitleHostAndPathButNeverQueryOrFragment() throws {
        let address = try XCTUnwrap(
            URL(string: "https://mail.example.com/inbox/thread?token=secret-token&email=person@example.com#draft-7"))
        let candidate = try XCTUnwrap(TidyTabCandidate(tabID: UUID(), pageTitle: "Trip plans", address: address))

        XCTAssertEqual(candidate.modelDescription, "Trip plans — mail.example.com/inbox/thread")
        XCTAssertNil(TidyTabCandidate(tabID: UUID(), pageTitle: "Notes", address: URL(string: "about:blank")!))
    }
}
