import WebKit
import XCTest

@testable import CrestMobile

/// The credential bridge is shared, so the compact shell is where its field
/// geometry is actually exercised against WebKit: the compact shell draws a
/// band and ignores the rect, but it is the same script reporting it.
@MainActor
final class MobileBrowserCredentialFieldAnchorTests: XCTestCase {
    func testSharedBridgeReportsTheFocusedFieldRectAndFollowsAScroll() async throws {
        let space = makeSpace()
        let page = MobileBrowserPage(tab: space.tabs[0], space: space, openNewTab: { _ in })
        page.webView.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        page.webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://forms.crest.test/login"))),
            responseHTML: Self.anchoredLoginDocument
        )
        try await waitUntil { page.completedNavigationCount == 1 }

        let didFocus = try await page.webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.focusForTesting(selector) === true;",
            arguments: ["selector": "#anchored-password"],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        XCTAssertEqual(didFocus as? Bool, true)
        try await waitUntil { page.credentialFillRequest?.fieldRect != nil }

        let focused = try XCTUnwrap(page.credentialFillRequest?.fieldRect)
        XCTAssertEqual(focused.width, 240, accuracy: 1)
        XCTAssertEqual(focused.height, 30, accuracy: 1)
        XCTAssertEqual(focused.x, 60, accuracy: 1)

        _ = try await page.webView.callAsyncJavaScript(
            "document.querySelector('#scroller').scrollTop = 400; return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil {
            page.credentialFillRequest?.fieldRect.map { $0.y != focused.y } ?? false
        }

        let followed = try XCTUnwrap(page.credentialFillRequest?.fieldRect)
        XCTAssertEqual(followed.y, focused.y - 400, accuracy: 1)
        XCTAssertEqual(followed.x, focused.x, accuracy: 1)
        page.dismissCredentialFillRequest()
    }

    func testTheCompactShellKeepsItsBandRatherThanAnchoringToTheField() {
        let touch = BrowserCredentialPromptMetrics.resolve(
            BrowserInteractionCapabilities(supportsHover: true, supportsTouch: true)
        )

        XCTAssertEqual(touch, .touch)
        XCTAssertFalse(touch.anchorsFillPromptToField)
        XCTAssertEqual(touch.chromeInset, 0)
        XCTAssertEqual(touch.surfaceStyle, .band)
        XCTAssertEqual(touch.closeControlSize, 44)
        XCTAssertEqual(touch.suggestionRowMinimumHeight, 44)
        XCTAssertEqual(touch.suggestionRowHighlightBleed, 0)
        XCTAssertNil(touch.suggestionRowHighlightCornerRadius)
        XCTAssertFalse(touch.suggestionRowShowsAccountDetail)
        XCTAssertEqual(touch.suggestionEmptyStatePresentation, .sentence)
    }

    private static let anchoredLoginDocument = """
        <!doctype html>
        <style>
          body { margin: 0; }
          #scroller { height: 300px; overflow: auto; }
          .spacer { height: 900px; }
          input {
            display: block;
            box-sizing: border-box;
            width: 240px;
            height: 30px;
            margin-left: 60px;
            padding: 0;
            border: 0;
          }
        </style>
        <div id="scroller">
          <div class="spacer"></div>
          <form id="anchored-login">
            <input autocomplete="username" value="person@example.com">
            <input id="anchored-password" type="password" autocomplete="current-password">
          </form>
          <div class="spacer"></div>
        </div>
        """

    private func makeSpace() -> BrowserSpace {
        let tab = BrowserTab(
            id: TabID(rawValue: fixedUUID(1)),
            title: "New Tab",
            url: nil,
            placement: .current
        )
        return BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(2)),
            profile: BrowsingProfile(id: fixedUUID(3)),
            name: "Anchor",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value)) ?? UUID()
    }

    private func waitUntil(
        timeout: Duration = .seconds(8),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the shared credential bridge's field geometry")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
