import CoreGraphics
import Foundation
import WebKit
import XCTest

@testable import Crest

/// The geometry that puts a fill prompt under the field that asked for it: what
/// the page is allowed to say about where its field is, what the page state
/// does with it, and where the panel lands once it knows.
@MainActor
final class BrowserCredentialFieldAnchorTests: XCTestCase {
    func testFieldGeometryContractCarriesARectAndNothingElse() throws {
        let moved = try XCTUnwrap(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "fieldGeometry",
                    "trusted": false,
                    "formID": "form-1",
                    "fieldRect": ["x": 40, "y": 320, "width": 220, "height": 32],
                ]
            )
        )
        XCTAssertEqual(moved.fieldRect?.x, 40)
        XCTAssertEqual(moved.fieldRect?.y, 320)
        XCTAssertEqual(moved.fieldRect?.width, 220)
        XCTAssertEqual(moved.fieldRect?.height, 32)
        XCTAssertNil(moved.password)

        XCTAssertNil(
            BrowserCredentialFormMessage(
                body: ["version": 1, "event": "fieldGeometry", "formID": "form-1"]
            )
        )
        XCTAssertNil(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "fieldGeometry",
                    "fieldRect": ["x": 40, "y": 320, "width": 220, "height": 32],
                ]
            )
        )
        XCTAssertNil(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "fieldGeometry",
                    "formID": "form-1",
                    "fieldRect": ["x": 40, "y": 320, "width": 220, "height": 32],
                    "password": "must-not-ride-along",
                ]
            )
        )
        XCTAssertNil(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "fieldGeometry",
                    "formID": "form-1",
                    "fieldRect": ["x": 40, "y": 320, "width": 220, "height": 32],
                    "username": "must-not-ride-along",
                ]
            )
        )
    }

    func testFieldRectRejectsUnusableAndUnboundedGeometry() throws {
        let focus = try XCTUnwrap(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "focus",
                    "trusted": true,
                    "formID": "form-1",
                    "passwordKind": "current",
                    "fieldRect": ["x": -12, "y": 8, "width": 220, "height": 32],
                ]
            )
        )
        XCTAssertEqual(focus.fieldRect?.x, -12)

        // A focus is still a focus without a usable rect. It just cannot be
        // anchored, so the prompt keeps the placement it has without one.
        let unmeasured = try XCTUnwrap(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "focus",
                    "trusted": true,
                    "formID": "form-1",
                    "passwordKind": "current",
                    "fieldRect": ["x": 0, "y": 0, "width": 0, "height": 32],
                ]
            )
        )
        XCTAssertNil(unmeasured.fieldRect)

        XCTAssertNil(
            BrowserCredentialFieldRect(
                body: ["x": 0, "y": 0, "width": 220, "height": Double.nan]
            )
        )
        XCTAssertNil(
            BrowserCredentialFieldRect(
                body: ["x": 0, "y": 0, "width": 220, "height": Double.infinity]
            )
        )
        XCTAssertNil(
            BrowserCredentialFieldRect(
                body: [
                    "x": BrowserCredentialFieldRect.coordinateLimit + 1,
                    "y": 0,
                    "width": 220,
                    "height": 32,
                ]
            )
        )
        XCTAssertNil(
            BrowserCredentialFieldRect(body: ["x": "0", "y": 0, "width": 220, "height": 32])
        )
        XCTAssertNil(BrowserCredentialFieldRect(body: ["x": 0, "y": 0, "width": 220]))
    }

    func testOnlyAMainFrameFieldAnchorsItsPromptAndOnlyItsOwnFormMovesIt() throws {
        let spaceID = SpaceID()
        let loginOrigin = try origin("https://accounts.example.com/login")
        let framedOrigin = try origin("https://embedded.example.com/login")
        let state = BrowserCredentialPageState<String>(spaceID: spaceID)

        state.receive(
            try focusMessage(formID: "login-form", x: 40, y: 300),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        let request = try XCTUnwrap(state.fillRequest)
        XCTAssertEqual(request.fieldRect?.y, 300)

        // Another form's report, and a report from another origin, are about
        // some other field entirely.
        state.receive(
            try geometryMessage(formID: "other-form", y: 10),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        state.receive(
            try geometryMessage(formID: "login-form", y: 20),
            frameOrigin: framedOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        // A subframe's coordinates say nothing about where the page is.
        state.receive(
            try geometryMessage(formID: "login-form", y: 30),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: false,
            fillTarget: "sub-frame"
        )
        XCTAssertEqual(state.fillRequest, request)

        state.receive(
            try geometryMessage(formID: "login-form", y: 120),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        let followed = try XCTUnwrap(state.fillRequest)
        XCTAssertEqual(followed.fieldRect?.y, 120)
        XCTAssertEqual(followed.id, request.id, "Following a field must not re-arm the request.")
        XCTAssertEqual(followed.requestedAt, request.requestedAt)

        // A frame's own rect is never taken for the page's.
        let framed = BrowserCredentialPageState<String>(spaceID: spaceID)
        framed.receive(
            try focusMessage(formID: "framed-form", x: 8, y: 12),
            frameOrigin: framedOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: false,
            fillTarget: "sub-frame"
        )
        XCTAssertNotNil(framed.fillRequest)
        XCTAssertNil(framed.fillRequest?.fieldRect)
    }

    func testDismissingAPromptStopsItsFieldFromBeingFollowed() throws {
        let loginOrigin = try origin("https://accounts.example.com/login")
        let state = BrowserCredentialPageState<String>(spaceID: SpaceID())
        state.receive(
            try focusMessage(formID: "login-form", x: 40, y: 300),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        state.dismissFillRequest()

        state.receive(
            try geometryMessage(formID: "login-form", y: 120),
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        XCTAssertNil(state.fillRequest)
    }

    func testAnchoredPromptSitsUnderItsFieldAndFlipsRatherThanLeaveThePage() {
        let container = CGSize(width: 1_000, height: 700)
        let size = CGSize(width: 320, height: 180)
        let inset: CGFloat = 12
        let gap = BrowserCredentialPromptMetrics.fieldAnchorGap

        let below = BrowserCredentialPromptAnchorPolicy.resolve(
            field: CGRect(x: 120, y: 200, width: 240, height: 32),
            size: size,
            container: container,
            gap: gap,
            inset: inset
        )
        XCTAssertFalse(below.isAboveField)
        XCTAssertEqual(below.origin.x, 120)
        XCTAssertEqual(below.origin.y, 232 + gap)

        let flipped = BrowserCredentialPromptAnchorPolicy.resolve(
            field: CGRect(x: 120, y: 600, width: 240, height: 32),
            size: size,
            container: container,
            gap: gap,
            inset: inset
        )
        XCTAssertTrue(flipped.isAboveField)
        XCTAssertEqual(flipped.origin.y, 600 - gap - 180)

        // A field against the trailing edge pulls the panel back inside.
        let pulledBack = BrowserCredentialPromptAnchorPolicy.resolve(
            field: CGRect(x: 940, y: 200, width: 40, height: 32),
            size: size,
            container: container,
            gap: gap,
            inset: inset
        )
        XCTAssertEqual(pulledBack.origin.x, 1_000 - 12 - 320)

        // Nowhere to put it: below, pushed back inside, never off the page.
        let cramped = BrowserCredentialPromptAnchorPolicy.resolve(
            field: CGRect(x: 10, y: 40, width: 240, height: 32),
            size: size,
            container: CGSize(width: 260, height: 150),
            gap: gap,
            inset: inset
        )
        XCTAssertFalse(cramped.isAboveField)
        XCTAssertEqual(cramped.origin, CGPoint(x: inset, y: inset))
    }

    func testAnchoredPromptTakesTheFieldsWidthInsideTheProfilesBounds() {
        let container = CGSize(width: 1_000, height: 700)
        XCTAssertEqual(BrowserCredentialPromptMetrics.pointer.anchoredFillPromptMinimumWidth, 264)
        XCTAssertEqual(BrowserCredentialPromptMetrics.pointer.fillPromptWidth.boundedWidth, 360)

        XCTAssertEqual(
            BrowserCredentialPromptAnchorPolicy.width(
                field: CGRect(x: 0, y: 0, width: 300, height: 32),
                container: container,
                minimumWidth: 264,
                maximumWidth: 360,
                inset: 12
            ),
            300
        )
        XCTAssertEqual(
            BrowserCredentialPromptAnchorPolicy.width(
                field: CGRect(x: 0, y: 0, width: 120, height: 32),
                container: container,
                minimumWidth: 264,
                maximumWidth: 360,
                inset: 12
            ),
            264
        )
        XCTAssertEqual(
            BrowserCredentialPromptAnchorPolicy.width(
                field: CGRect(x: 0, y: 0, width: 900, height: 32),
                container: container,
                minimumWidth: 264,
                maximumWidth: 360,
                inset: 12
            ),
            360
        )
        XCTAssertEqual(
            BrowserCredentialPromptAnchorPolicy.width(
                field: CGRect(x: 0, y: 0, width: 900, height: 32),
                container: CGSize(width: 220, height: 400),
                minimumWidth: 264,
                maximumWidth: 360,
                inset: 12
            ),
            196
        )
    }

    func testOnlyThePointerProfileAnchorsAFillPromptToItsField() {
        let pointer = BrowserCredentialPromptMetrics.pointer
        let touch = BrowserCredentialPromptMetrics.touch

        XCTAssertTrue(pointer.anchorsFillPromptToField)
        XCTAssertEqual(pointer.chromeInset, CrestSpacing.medium)
        XCTAssertEqual(pointer.suggestionEmptyStatePresentation, .compact)
        XCTAssertEqual(pointer.narrowingFillPrompt(to: 288).fillPromptWidth, .fixed(288))

        XCTAssertFalse(touch.anchorsFillPromptToField)
        XCTAssertEqual(touch.chromeInset, 0)
        XCTAssertNil(touch.anchoredFillPromptMinimumWidth)
        XCTAssertNil(touch.suggestionRowHighlightCornerRadius)
        XCTAssertEqual(touch.suggestionRowHighlightBleed, 0)
        XCTAssertFalse(touch.suggestionRowShowsAccountDetail)
        XCTAssertEqual(touch.closeControlSize, 44)
        XCTAssertEqual(touch.suggestionEmptyStatePresentation, .sentence)
    }

    func testOnlyAFillPromptHasAFieldToPointAt() throws {
        let loginOrigin = try origin("https://accounts.example.com/login")
        let request = BrowserCredentialFillRequest(
            id: UUID(),
            origin: loginOrigin,
            topLevelOrigin: loginOrigin,
            usernameHint: nil,
            passwordKind: .current,
            isCrossOriginFrame: false,
            requestedAt: Date(timeIntervalSince1970: 1_000),
            fieldRect: BrowserCredentialFieldRect(x: 8, y: 16, width: 220, height: 32)
        )
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: loginOrigin,
            topLevelOrigin: loginOrigin,
            username: "person@example.com",
            password: "secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(
            BrowserCredentialChromePresentation.suggestions(request).fillRequest,
            request
        )
        XCTAssertEqual(
            BrowserCredentialChromePresentation.strongPassword(request).fillRequest,
            request
        )
        XCTAssertNil(BrowserCredentialChromePresentation.save(candidate).fillRequest)
        XCTAssertNil(BrowserCredentialChromePresentation.none.fillRequest)
    }

    func testCredentialContentBridgeReportsAndFollowsTheFocusedField() {
        let source = BrowserCredentialContentBridge.source

        XCTAssertTrue(source.contains("event: \"fieldGeometry\""))
        XCTAssertTrue(source.contains("getBoundingClientRect"))
        XCTAssertTrue(source.contains("new WeakRef(input)"))
        XCTAssertTrue(source.contains("{ capture: true, passive: true }"))
        XCTAssertFalse(source.contains("setInterval"))
    }

    func testIsolatedBridgeReportsTheFocusedFieldAndFollowsItAsThePageScrolls() async throws {
        let focusExpectation = expectation(description: "focused field rect")
        let scrollExpectation = expectation(description: "field followed a scroll")
        let messages = CredentialFieldRectRecorder(
            onFocus: { focusExpectation.fulfill() },
            onGeometry: { scrollExpectation.fulfill() }
        )
        let webView = try await credentialBridgeWebView { scriptMessage in
            messages.record(BrowserCredentialFormMessage(body: scriptMessage.body))
        }

        let didFocus = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.focusForTesting(selector) === true;",
            arguments: ["selector": "#anchored-password"],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        XCTAssertEqual(didFocus as? Bool, true)
        await fulfillment(of: [focusExpectation], timeout: 4)

        let focused = try XCTUnwrap(messages.focusRect)
        XCTAssertEqual(focused.width, 240, accuracy: 1)
        XCTAssertEqual(focused.height, 30, accuracy: 1)
        XCTAssertEqual(focused.x, 60, accuracy: 1)
        XCTAssertGreaterThan(focused.y, 0)

        _ = try await webView.callAsyncJavaScript(
            "document.querySelector('#scroller').scrollTop = 400; return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        await fulfillment(of: [scrollExpectation], timeout: 4)

        let followed = try XCTUnwrap(messages.geometryRect)
        XCTAssertEqual(
            followed.y,
            focused.y - 400,
            accuracy: 1,
            "A scrolled field reports the viewport position it actually moved to."
        )
        XCTAssertEqual(followed.x, focused.x, accuracy: 1)
    }

    // MARK: - Fixtures

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

    private func origin(_ string: String) throws -> CredentialOrigin {
        try XCTUnwrap(CredentialOrigin(url: XCTUnwrap(URL(string: string))))
    }

    private func focusMessage(
        formID: String,
        x: Double,
        y: Double
    ) throws -> BrowserCredentialFormMessage {
        try XCTUnwrap(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "focus",
                    "trusted": true,
                    "formID": formID,
                    "passwordKind": "current",
                    "fieldRect": ["x": x, "y": y, "width": 220, "height": 32],
                ]
            )
        )
    }

    private func geometryMessage(
        formID: String,
        y: Double
    ) throws -> BrowserCredentialFormMessage {
        try XCTUnwrap(
            BrowserCredentialFormMessage(
                body: [
                    "version": 1,
                    "event": "fieldGeometry",
                    "formID": formID,
                    "fieldRect": ["x": 40, "y": y, "width": 220, "height": 32],
                ]
            )
        )
    }

    private func credentialBridgeWebView(
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        _ = BrowserCredentialContentBridge.install(
            in: configuration.userContentController,
            receive: receive
        )
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        let waiter = CredentialFieldAnchorNavigationWaiter(webView: webView)
        try await waiter.load(
            simulatedRequest: URLRequest(
                url: try XCTUnwrap(URL(string: "https://forms.crest.test/"))
            ),
            responseHTML: Self.anchoredLoginDocument
        )
        return webView
    }
}

/// Keeps the first rect a focus reported and the latest one a scroll did, so a
/// test can compare where the field was against where it went.
@MainActor
private final class CredentialFieldRectRecorder {
    private(set) var focusRect: BrowserCredentialFieldRect?
    private(set) var geometryRect: BrowserCredentialFieldRect?

    private let onFocus: @MainActor () -> Void
    private let onGeometry: @MainActor () -> Void
    private var hasReportedGeometry = false

    init(
        onFocus: @escaping @MainActor () -> Void,
        onGeometry: @escaping @MainActor () -> Void
    ) {
        self.onFocus = onFocus
        self.onGeometry = onGeometry
    }

    func record(_ message: BrowserCredentialFormMessage?) {
        guard let message, let fieldRect = message.fieldRect else { return }
        switch message.event {
        case .focus:
            guard focusRect == nil else { return }
            focusRect = fieldRect
            onFocus()
        case .fieldGeometry:
            geometryRect = fieldRect
            guard !hasReportedGeometry else { return }
            hasReportedGeometry = true
            onGeometry()
        case .username, .submit, .documentState:
            break
        }
    }
}

@MainActor
private final class CredentialFieldAnchorNavigationWaiter: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func load(simulatedRequest request: URLRequest, responseHTML: String) async throws {
        guard let webView else { throw CredentialFieldAnchorWaiterError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadSimulatedRequest(request, responseHTML: responseHTML)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private enum CredentialFieldAnchorWaiterError: Error {
    case releasedWebView
}
