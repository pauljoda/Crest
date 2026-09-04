import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionHostedPageConfigurationPolicyTests: XCTestCase {
    func testClearingTheModeLeavesEveryDocumentUnderItsOwnPolicy() throws {
        let configuration = WKWebViewConfiguration()
        guard BrowserExtensionHostedPageConfigurationPolicy.isSupported(by: configuration) else {
            throw XCTSkip("This WebKit does not expose the extension CSP mode.")
        }
        XCTAssertTrue(
            BrowserExtensionHostedPageConfigurationPolicy.setExtensionContentSecurityPolicyMode(
                .manifestV3, on: configuration))
        XCTAssertEqual(
            BrowserExtensionHostedPageConfigurationPolicy.extensionContentSecurityPolicyMode(of: configuration),
            .manifestV3, "WebKit's configuration for an MV3 extension carries the mode Crest must clear.")
        XCTAssertTrue(
            BrowserExtensionHostedPageConfigurationPolicy.clearExtensionContentSecurityPolicyMode(on: configuration))
        XCTAssertEqual(
            BrowserExtensionHostedPageConfigurationPolicy.extensionContentSecurityPolicyMode(of: configuration),
            BrowserExtensionHostedPageConfigurationPolicy.Mode.none)
    }

    func testAFreshConfigurationStartsWithoutAnExtensionMode() throws {
        let configuration = WKWebViewConfiguration()
        guard BrowserExtensionHostedPageConfigurationPolicy.isSupported(by: configuration) else {
            throw XCTSkip("This WebKit does not expose the extension CSP mode.")
        }
        XCTAssertEqual(
            BrowserExtensionHostedPageConfigurationPolicy.extensionContentSecurityPolicyMode(of: configuration),
            BrowserExtensionHostedPageConfigurationPolicy.Mode.none)
    }
}
