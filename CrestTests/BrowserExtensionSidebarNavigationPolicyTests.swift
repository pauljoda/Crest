import XCTest

@testable import Crest

final class BrowserExtensionSidebarNavigationPolicyTests: XCTestCase {
    func testOwnOriginAndBlankStayInsideTheUnannouncedDocument() throws {
        let base = try XCTUnwrap(URL(string: "webkit-extension://panel/"))
        for target in ["webkit-extension://panel/nested.html", "about:blank"] {
            XCTAssertEqual(
                BrowserExtensionSidebarNavigationPolicy.decide(
                    url: URL(string: target)!, extensionBaseURL: base, isMainFrame: true, opensNewWindow: false
                ), .allow)
        }
    }

    func testTopLevelWebLinksBecomeTabsWhileFramesStayGovernedByWebKit() throws {
        let base = try XCTUnwrap(URL(string: "webkit-extension://panel/"))
        let web = try XCTUnwrap(URL(string: "https://example.com/"))
        XCTAssertEqual(
            BrowserExtensionSidebarNavigationPolicy.decide(
                url: web, extensionBaseURL: base, isMainFrame: true, opensNewWindow: false
            ), .openTab)
        XCTAssertEqual(
            BrowserExtensionSidebarNavigationPolicy.decide(
                url: web, extensionBaseURL: base, isMainFrame: false, opensNewWindow: false
            ), .allow)
        XCTAssertEqual(
            BrowserExtensionSidebarNavigationPolicy.decide(
                url: web, extensionBaseURL: base, isMainFrame: false, opensNewWindow: true
            ), .openTab)
    }

    func testForeignExtensionAndPrivilegedSchemesAreRefused() throws {
        let base = try XCTUnwrap(URL(string: "webkit-extension://panel/"))
        for target in [
            "webkit-extension://other/panel.html", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,test",
        ] {
            XCTAssertEqual(
                BrowserExtensionSidebarNavigationPolicy.decide(
                    url: URL(string: target)!, extensionBaseURL: base, isMainFrame: true, opensNewWindow: false
                ), .cancel)
        }
    }
}
