import Foundation
import XCTest

@testable import Crest

final class BrowserLinkContextCapturePolicyTests: XCTestCase {
    func testARecordedLinkIsHandedToExactlyOneMenu() throws {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/article"))

        XCTAssertEqual(
            policy.pendingLink,
            URL(string: "https://example.com/article"),
            "Reading without taking leaves the capture for the menu."
        )
        XCTAssertEqual(
            policy.takeLink(),
            URL(string: "https://example.com/article")
        )
        XCTAssertNil(
            policy.takeLink(),
            "A second menu must never inherit the first menu's link."
        )
        XCTAssertNil(policy.pendingLink)
    }

    func testARightClickWithoutALinkEmptiesTheSlot() {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/article"))
        policy.record(body: makeBody(href: nil))

        XCTAssertNil(
            policy.takeLink(),
            "Plain content reports itself so the previous link cannot leak."
        )
    }

    func testAClosingMenuDropsAnUnusedCapture() {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/article"))
        policy.clear()

        XCTAssertNil(policy.pendingLink)
        XCTAssertNil(policy.takeLink())
    }

    func testALaterRightClickReplacesAnEarlierCapture() throws {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/first"))
        policy.record(body: makeBody(href: "https://example.com/second"))

        XCTAssertEqual(
            policy.takeLink(),
            URL(string: "https://example.com/second")
        )
    }

    func testACapturedLinkSurvivesAClearedPredecessor() throws {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/first"))
        policy.clear()
        policy.record(body: makeBody(href: "https://example.com/second"))

        XCTAssertEqual(
            policy.takeLink(),
            URL(string: "https://example.com/second"),
            "Clearing retires the previous report, not the whole bridge."
        )
    }

    func testOnlyWebSchemesAreCaptured() {
        let refused = [
            "javascript:alert(1)",
            "data:text/html,<b>hi</b>",
            "file:///etc/passwd",
            "mailto:someone@example.com",
            "about:blank",
            "crest-extension-install://chrome-web-store/abc",
            "https:///no-host",
        ]
        for href in refused {
            var policy = BrowserLinkContextCapturePolicy()
            policy.record(body: makeBody(href: href))
            XCTAssertNil(
                policy.takeLink(),
                "\(href) is not a destination the new-tab path would accept."
            )
        }
    }

    func testMalformedPayloadsAreRefused() {
        let refused: [Any] = [
            "https://example.com/article",
            ["version": 1] as [String: Any],
            ["version": 2, "href": "https://example.com/article"] as [String: Any],
            ["href": "https://example.com/article"] as [String: Any],
            ["version": 1, "href": 17] as [String: Any],
            ["version": "1", "href": "https://example.com/article"] as [String: Any],
            [
                "version": 1,
                "href": "https://example.com/\(String(repeating: "a", count: 4_096))",
            ] as [String: Any],
        ]
        for body in refused {
            var policy = BrowserLinkContextCapturePolicy()
            policy.record(body: body)
            XCTAssertNil(
                policy.takeLink(),
                "A payload the script never sends must not reach the menu."
            )
        }
    }

    func testAMalformedPayloadStillRetiresTheCaptureBeforeIt() {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/article"))
        policy.record(body: "not a dictionary")

        XCTAssertNil(
            policy.takeLink(),
            "A report Crest cannot read is still a new right-click."
        )
    }

    private func makeBody(href: String?) -> [String: Any] {
        var body: [String: Any] = [
            "version": BrowserLinkContextCapturePolicy.contractVersion,
            "token": 1,
        ]
        body["href"] = href ?? NSNull()
        return body
    }
}
