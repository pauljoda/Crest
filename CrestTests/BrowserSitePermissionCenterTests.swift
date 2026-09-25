import XCTest

@testable import Crest

/// The permission rules, their adoption from defaults, the lock gate and what
/// the device store keeps are core contracts (`SitePermissionLedgerTests` and
/// `SitePermissionStoreTests` in CrestCore). The platform still spells an
/// origin itself until S6 replaces `BrowserSiteOrigin` with the core's, and
/// the core compares the origins it returns with the ones pages report.
@MainActor
final class BrowserSitePermissionCenterTests: XCTestCase {
    func testOriginNormalizationPreservesWebDefaultsAndUnknownPorts() throws {
        XCTAssertEqual(
            BrowserSiteOrigin(scheme: "HTTP", host: "News.Example", port: 0),
            BrowserSiteOrigin(scheme: "http", host: "news.example", port: 80)
        )
        XCTAssertEqual(
            BrowserSiteOrigin(scheme: "HTTPS", host: "News.Example", port: -1),
            BrowserSiteOrigin(scheme: "https", host: "news.example", port: 443)
        )
        XCTAssertEqual(
            BrowserSiteOrigin(scheme: "custom", host: "Handler.Example", port: 0),
            BrowserSiteOrigin(scheme: "custom", host: "handler.example", port: 0)
        )
        XCTAssertEqual(
            BrowserSiteOrigin(url: try XCTUnwrap(URL(string: "https://News.Example/path"))),
            BrowserSiteOrigin(scheme: "https", host: "news.example", port: 443)
        )
        XCTAssertNil(BrowserSiteOrigin(url: URL(fileURLWithPath: "/tmp/index.html")))
    }
}
