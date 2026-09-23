import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserCredentialTests: XCTestCase {
    func testMobilePageInstallsTheSharedCredentialBridgeInEveryFrame() {
        let space = makeSpace(index: 1)
        let page = MobileBrowserPage(tab: space.tabs[0], space: space, openNewTab: { _ in })
        let scripts = page.webView.configuration.userContentController.userScripts

        XCTAssertTrue(
            scripts.contains {
                $0.source == BrowserCredentialContentBridge.source
                    && $0.injectionTime == .atDocumentStart
                    && !$0.isForMainFrameOnly
            })
    }

    func testMobilePageReceivesASuccessfulIsolatedWorldFormSubmission() async throws {
        let space = makeSpace(index: 7)
        let page = MobileBrowserPage(tab: space.tabs[0], space: space, openNewTab: { _ in })
        let request = URLRequest(url: URL(string: "https://forms.crest.test/login")!)
        page.webView.loadSimulatedRequest(
            request,
            responseHTML: """
                <!doctype html>
                <style>input { display: block; width: 220px; height: 32px; }</style>
                <form id="mobile-login">
                  <input autocomplete="username" value="mobile@example.com">
                  <input type="password" autocomplete="current-password" value="mobile-secret">
                  <button type="button">Sign In</button>
                </form>
                """)
        try await waitUntil { page.completedNavigationCount == 1 }

        let didCapture = try await page.webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.captureForTesting(selector) === true;",
            arguments: ["selector": "#mobile-login"],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        XCTAssertEqual(didCapture as? Bool, true)
        XCTAssertNil(page.credentialSaveCandidate)

        _ = try await page.webView.callAsyncJavaScript(
            "document.querySelector('#mobile-login').remove(); return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil { page.credentialSaveCandidate != nil }

        let candidate = try XCTUnwrap(page.credentialSaveCandidate)
        XCTAssertEqual(candidate.username, "mobile@example.com")
        XCTAssertEqual(candidate.password, "mobile-secret")
        XCTAssertEqual(candidate.origin, try origin("https://forms.crest.test/login"))
        XCTAssertFalse(candidate.description.contains("mobile-secret"))
        page.dismissCredentialSaveCandidate()
    }

    private func origin(_ value: String) throws -> CredentialOrigin {
        try XCTUnwrap(CredentialOrigin(url: try XCTUnwrap(URL(string: value))))
    }

    private func makeSpace(index: Int) -> BrowserSpace {
        let tab = BrowserTab(
            id: TabID(rawValue: fixedUUID(index * 10 + 1)),
            title: "New Tab",
            url: nil,
            placement: .current
        )
        return BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(index * 10 + 2)),
            profile: BrowsingProfile(id: fixedUUID(index * 10 + 3)),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    private func waitUntil(
        timeout: Duration = .seconds(8),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the mobile WebKit credential state")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
