import Foundation
import XCTest
@testable import Crest

@MainActor
final class BrowserDialogPresenterTests: XCTestCase {
    func testSourceLabelUsesHostAndNondefaultPort() throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:8765/compatibility.html"))

        XCTAssertEqual(BrowserDialogPresenter.sourceLabel(for: URLRequest(url: url)), "127.0.0.1:8765")
    }

    func testSourceLabelOmitsDefaultPortAndFallsBackForOpaqueRequests() throws {
        let secureURL = try XCTUnwrap(URL(string: "https://example.com/account"))
        let fileURL = URL(fileURLWithPath: "/tmp/local.html")

        XCTAssertEqual(BrowserDialogPresenter.sourceLabel(for: URLRequest(url: secureURL)), "example.com")
        XCTAssertEqual(BrowserDialogPresenter.sourceLabel(for: URLRequest(url: fileURL)), ProductIdentity.name)
    }
}
