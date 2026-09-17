import XCTest
@testable import Crest

@MainActor
final class BrowserDefaultBrowserTests: XCTestCase {
    func testExternalURLPolicyAcceptsOnlyHostBasedHTTPAndHTTPSURLs() throws {
        XCTAssertTrue(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "https://example.com/path?q=1"))
            )
        )
        XCTAssertTrue(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "http://127.0.0.1:8765/fixture"))
            )
        )
        XCTAssertFalse(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "file:///tmp/index.html"))
            )
        )
        XCTAssertFalse(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "crest://settings"))
            )
        )
        XCTAssertFalse(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "https:///missing-host"))
            )
        )
    }

    func testExternalURLReusesASelectedStartPageThenCreatesANewCurrentTab() throws {
        let browser = BrowserStore.privateBrowsing()
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/second"))
        let originalTabID = try XCTUnwrap(browser.selectedTab?.id)

        XCTAssertTrue(browser.openExternalURL(firstURL))
        XCTAssertEqual(browser.selectedTab?.id, originalTabID)
        XCTAssertEqual(browser.selectedTab?.url, firstURL)
        XCTAssertEqual(browser.selectedSpace?.currentTabs.count, 1)

        XCTAssertTrue(browser.openExternalURL(secondURL))
        XCTAssertNotEqual(browser.selectedTab?.id, originalTabID)
        XCTAssertEqual(browser.selectedTab?.url, secondURL)
        XCTAssertEqual(browser.selectedSpace?.currentTabs.count, 2)
    }

    func testDefaultBrowserControllerOwnsExplicitStatusAndRequestFlow() async {
        var isSystemDefault = false
        var requestCount = 0
        let controller = BrowserDefaultBrowserController(
            requestStyle: .direct,
            statusCheck: { isSystemDefault },
            defaultRequest: {
                requestCount += 1
                isSystemDefault = true
            },
            settingsOpener: {}
        )

        XCTAssertEqual(controller.status, .unknown)
        controller.refreshStatus()
        XCTAssertEqual(controller.status, .notDefault)

        await controller.requestDefault()

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(controller.status, .isDefault)
        XCTAssertFalse(controller.isWorking)
    }
}
