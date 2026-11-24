import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialFormTests: XCTestCase {
    private static let loginFields: [[String: Any]] = [
        [
            "index": 0, "type": "text", "autocomplete": "username", "name": "user", "id": "", "label": "",
            "placeholder": "", "visible": true, "hasValue": true, "entered": true,
        ],
        [
            "index": 1, "type": "password", "autocomplete": "current-password", "name": "pass", "id": "", "label": "",
            "placeholder": "", "visible": true, "hasValue": true, "entered": true,
        ],
    ]

    func testFocusMessageRequiresATrustedGestureAndNeverAcceptsAPassword() throws {
        let focus: [String: Any] = [
            "version": 2, "event": "focus", "trusted": true, "formID": "form-1", "readingID": 3,
            "fields": Self.loginFields, "focusedField": 0, "values": ["0": "person@example.com"],
        ]
        let valid = try XCTUnwrap(BrowserCredentialFormMessage(body: focus))
        XCTAssertEqual(valid.event, .focus)
        XCTAssertEqual(valid.formID, "form-1")
        XCTAssertEqual(valid.readingID, 3)
        XCTAssertEqual(valid.fields.map(\.inputType), [.text, .password])
        XCTAssertEqual(valid.value(at: 0), "person@example.com")

        var untrusted = focus
        untrusted["trusted"] = false
        XCTAssertNil(BrowserCredentialFormMessage(body: untrusted))
        var unfocused = focus
        unfocused["focusedField"] = 5
        XCTAssertNil(BrowserCredentialFormMessage(body: unfocused))
        var unread = focus
        unread["readingID"] = nil
        XCTAssertNil(BrowserCredentialFormMessage(body: unread))
        var exfiltrating = focus
        exfiltrating["values"] = ["0": "person@example.com", "1": "page-tried-to-exfiltrate-this"]
        XCTAssertNil(BrowserCredentialFormMessage(body: exfiltrating))
    }

    func testSubmitMessageRequiresCompleteTrustedFieldsAndRedactsItsSecret() throws {
        let submit: [String: Any] = [
            "version": 2, "event": "submit", "trusted": true, "formID": "form-7", "fields": Self.loginFields,
            "values": ["0": "person", "1": "correct horse battery staple"],
            "submission": ["trigger": "submitControl", "inForm": true, "label": "Sign in"],
        ]
        let message = try XCTUnwrap(BrowserCredentialFormMessage(body: submit))
        XCTAssertEqual(message.event, .submit)
        XCTAssertEqual(message.value(at: 1), "correct horse battery staple")
        XCTAssertEqual(message.submission?.trigger, .submitControl)
        XCTAssertFalse(message.description.contains("correct horse battery staple"))
        XCTAssertTrue(message.description.contains("<redacted>"))

        var untrusted = submit
        untrusted["trusted"] = false
        XCTAssertNil(BrowserCredentialFormMessage(body: untrusted))
        var unsent = submit
        unsent["submission"] = nil
        XCTAssertNil(BrowserCredentialFormMessage(body: unsent))
        var stray = submit
        stray["values"] = ["0": "person", "9": "not a field of this form"]
        XCTAssertNil(BrowserCredentialFormMessage(body: stray))
        var older = submit
        older["version"] = 1
        XCTAssertNil(BrowserCredentialFormMessage(body: older))
    }

    func testIsolatedBridgeReadsAndFillsAnOrdinaryLoginForm() async throws {
        let webView = try await credentialBridgeWebView(
            html: """
                <!doctype html>
                <style>input { display: block; width: 220px; height: 32px; }</style>
                <form id="login">
                  <input id="login-user" autocomplete="username" value="person@example.com">
                  <input id="login-password" type="password" autocomplete="current-password" value="old-secret">
                  <input type="search" name="q">
                </form>
                """)

        let inspectionResult = try await inspect("#login", in: webView)
        let inspection = try XCTUnwrap(inspectionResult)
        let pageWorldBridgeVisibility = try await webView.callAsyncJavaScript(
            "return typeof globalThis.__crestCredentialBridge;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        XCTAssertEqual(pageWorldBridgeVisibility as? String, "undefined")
        let fields = try XCTUnwrap(inspection["fields"] as? [[String: Any]])
        XCTAssertEqual(fields.compactMap { $0["type"] as? String }, ["text", "password"])
        XCTAssertEqual(fields.compactMap { $0["autocomplete"] as? String }, ["username", "current-password"])
        // A value the page put there is not one the person entered.
        XCTAssertEqual(fields.compactMap { $0["entered"] as? Bool }, [false, false])

        let formID = try XCTUnwrap(inspection["formID"] as? String)
        let readingID = try XCTUnwrap(inspection["readingID"] as? Int)
        let didFill = try await fill(
            formID: formID,
            readingID: readingID,
            entries: [["index": 0, "value": "filled@example.com"], ["index": 1, "value": "filled-secret"]],
            in: webView
        )
        XCTAssertTrue(didFill)
        let pageValues = try await pageJSON(
            """
            return JSON.stringify({
              username: document.querySelector('#login-user').value,
              password: document.querySelector('#login-password').value
            });
            """,
            in: webView
        )
        XCTAssertEqual(pageValues["username"] as? String, "filled@example.com")
        XCTAssertEqual(pageValues["password"] as? String, "filled-secret")
        let missingField = try await fill(
            formID: formID, readingID: readingID, entries: [["index": 7, "value": "x"]], in: webView)
        XCTAssertFalse(missingField)
        let staleReading = try await fill(
            formID: formID, readingID: readingID + 100, entries: [["index": 0, "value": "x"]], in: webView)
        XCTAssertFalse(staleReading)
    }

    private func credentialBridgeWebView(
        html: String,
        receive: @escaping @MainActor (WKScriptMessage) -> Void = { _ in }
    ) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        _ = BrowserCredentialContentBridge.install(
            in: configuration.userContentController,
            receive: receive
        )
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let waiter = CredentialBridgeNavigationWaiter(webView: webView)
        try await waiter.load(
            simulatedRequest: URLRequest(url: URL(string: "https://forms.crest.test/")!),
            responseHTML: html
        )
        return webView
    }

    private func inspect(_ selector: String, in webView: WKWebView) async throws -> [String: Any]? {
        let value = try await webView.callAsyncJavaScript(
            "return JSON.stringify(globalThis.__crestCredentialBridge?.inspectForTesting(selector) ?? null);",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        let json = try XCTUnwrap(value as? String)
        if json == "null" { return nil }
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fill(
        formID: String,
        readingID: Int,
        entries: [[String: Any]],
        in webView: WKWebView
    ) async throws -> Bool {
        let value = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.fill(formID, readingID, entries, false) === true;",
            arguments: [
                "formID": formID,
                "readingID": readingID,
                "entries": entries,
            ],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        return try XCTUnwrap(value as? Bool)
    }

    private func pageJSON(_ script: String, in webView: WKWebView) async throws -> [String: Any] {
        let value = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let json = try XCTUnwrap(value as? String)
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
private final class CredentialBridgeNavigationWaiter: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func load(simulatedRequest request: URLRequest, responseHTML: String) async throws {
        guard let webView else { throw CredentialBridgeNavigationWaiterError.releasedWebView }
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

private enum CredentialBridgeNavigationWaiterError: Error {
    case releasedWebView
}
