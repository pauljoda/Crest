import AppKit
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
            policy.take()?.linkURL,
            URL(string: "https://example.com/article")
        )
        XCTAssertNil(
            policy.take()?.linkURL,
            "A second menu must never inherit the first menu's link."
        )
        XCTAssertNil(policy.pendingLink)
    }

    func testARightClickWithoutALinkEmptiesTheSlot() {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/article"))
        policy.record(body: makeBody(href: nil))

        XCTAssertNil(
            policy.take()?.linkURL,
            "Plain content reports itself so the previous link cannot leak."
        )
    }

    func testAClosingMenuDropsAnUnusedCapture() {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/article"))
        policy.clear()

        XCTAssertNil(policy.pendingLink)
        XCTAssertNil(policy.take())
    }

    func testALaterRightClickReplacesAnEarlierCapture() throws {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/first"))
        policy.record(body: makeBody(href: "https://example.com/second"))

        XCTAssertEqual(
            policy.take()?.linkURL,
            URL(string: "https://example.com/second")
        )
    }

    func testACapturedLinkSurvivesAClearedPredecessor() throws {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/first"))
        policy.clear()
        policy.record(body: makeBody(href: "https://example.com/second"))

        XCTAssertEqual(
            policy.take()?.linkURL,
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
                policy.take()?.linkURL,
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
                policy.take()?.linkURL,
                "A payload the script never sends must not reach the menu."
            )
        }
    }

    func testAMalformedPayloadStillRetiresTheCaptureBeforeIt() {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(body: makeBody(href: "https://example.com/article"))
        policy.record(body: "not a dictionary")

        XCTAssertNil(
            policy.take()?.linkURL,
            "A report Crest cannot read is still a new right-click."
        )
    }

    func testImageAndLinkFromTheSameRightClickAreConsumedTogether() throws {
        var policy = BrowserLinkContextCapturePolicy()
        policy.record(
            body: makeBody(
                href: "https://example.com/article",
                imageURL: "https://cdn.example.com/photo.webp"
            )
        )

        XCTAssertEqual(
            policy.pendingImage,
            URL(string: "https://cdn.example.com/photo.webp")
        )
        let context = try XCTUnwrap(policy.take())
        XCTAssertEqual(context.linkURL, URL(string: "https://example.com/article"))
        XCTAssertEqual(
            context.imageURL,
            URL(string: "https://cdn.example.com/photo.webp")
        )
        XCTAssertNil(policy.take(), "One menu consumes both destinations.")
    }

    func testImageCaptureAcceptsPageDownloadSchemesButRefusesExecutableOnes() {
        let accepted = [
            "https://cdn.example.com/photo.webp",
            "http://localhost/photo.png",
            "blob:https://example.com/00000000-0000-4000-8000-000000000001",
            "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==",
        ]
        for imageURL in accepted {
            var policy = BrowserLinkContextCapturePolicy()
            policy.record(body: makeBody(imageURL: imageURL))
            XCTAssertEqual(policy.take()?.imageURL?.absoluteString, imageURL)
        }

        let refused = [
            "javascript:alert(1)",
            "file:///etc/passwd",
            "mailto:someone@example.com",
            "about:blank",
            "https:///no-host",
            "data:image/png;base64,\(String(repeating: "a", count: 4_096))",
        ]
        for imageURL in refused {
            var policy = BrowserLinkContextCapturePolicy()
            policy.record(body: makeBody(imageURL: imageURL))
            XCTAssertNil(policy.take()?.imageURL)
        }
    }

    @MainActor
    func testImageDownloadMenuLookupUsesWebKitsIdentifierInsteadOfItsTitle() {
        let menu = NSMenu()
        let unrelated = NSMenuItem(
            title: "Download Linked File",
            action: nil,
            keyEquivalent: ""
        )
        let imageDownload = NSMenuItem(
            title: "Localized Image Command",
            action: nil,
            keyEquivalent: ""
        )
        imageDownload.identifier =
            BrowserDesktopWebViewMenuPolicy.downloadImageIdentifier
        menu.items = [unrelated, imageDownload]

        XCTAssertTrue(
            BrowserDesktopWebViewMenuPolicy.downloadImageItem(in: menu)
                === imageDownload
        )
    }

    private func makeBody(
        href: String? = nil,
        imageURL: String? = nil
    ) -> [String: Any] {
        var body: [String: Any] = [
            "version": BrowserLinkContextCapturePolicy.contractVersion,
            "token": 1,
        ]
        body["href"] = href ?? NSNull()
        body["imageURL"] = imageURL ?? NSNull()
        return body
    }
}
