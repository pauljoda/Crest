import AppKit
import WebKit
import XCTest

@testable import Crest

/// Framework feasibility check, not an extension acceptance test. Only a
/// disposable, nonpersistent page is inspected; no extension API is published.
@MainActor
final class BrowserWebInspectorProtocolTests: XCTestCase {
    func testConnectionExecutesCommandsRejectsUnknownMethodsAndDisconnects() async throws {
        let page = try await disposablePage()
        let connection = BrowserWebInspectorProtocolConnection(webView: page)
        try await connection.connect()
        defer { connection.disconnect() }
        let response = try await connection.sendCommand(
            "Runtime.evaluate", parameters: ["expression": "6 * 7", "returnByValue": true])
        XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? Int, 42)
        do {
            _ = try await connection.sendCommand("CrestUnsupported.noSuchCommand")
            XCTFail("Unknown engine commands must reject instead of returning pretend success.")
        } catch {}
        connection.disconnect()
        do {
            _ = try await connection.sendCommand("Runtime.evaluate", parameters: ["expression": "1"])
            XCTFail("A disconnected connection must not execute commands.")
        } catch {
            XCTAssertEqual(error as? BrowserWebInspectorProtocolError, .notConnected)
        }
    }

    func testSecondConnectionCannotTakeOverAnExistingInspector() async throws {
        let page = try await disposablePage()
        let first = BrowserWebInspectorProtocolConnection(webView: page)
        try await first.connect()
        defer { first.disconnect() }
        let second = BrowserWebInspectorProtocolConnection(webView: page)
        do {
            try await second.connect()
            XCTFail("A second client must not hijack an existing Inspector connection.")
        } catch {
            XCTAssertEqual(error as? BrowserWebInspectorProtocolError, .alreadyConnected)
        }
        second.disconnect()
        let response = try await first.sendCommand(
            "Runtime.evaluate", parameters: ["expression": "document.title", "returnByValue": true])
        XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? String, "Crest inspector probe")
    }

    func testReleasingConnectionClosesItsEngineSession() async throws {
        let page = try await disposablePage()
        var connection: BrowserWebInspectorProtocolConnection? = .init(webView: page)
        weak var releasedConnection = connection
        try await connection?.connect()
        connection = nil
        XCTAssertNil(releasedConnection, "The message handler must not retain its connection.")

        let replacement = BrowserWebInspectorProtocolConnection(webView: page)
        try await replacement.connect()
        replacement.disconnect()
    }

    func testCancelledAttachmentCannotCloseItsReplacement() async throws {
        let page = try await disposablePage()
        let connection = BrowserWebInspectorProtocolConnection(webView: page)
        let first = Task { try await connection.connect() }
        await Task.yield()
        first.cancel()
        connection.disconnect()
        defer { connection.disconnect() }
        do {
            try await connection.connect()
        } catch {
            _ = await first.result
            throw error
        }
        _ = await first.result
        let response = try await connection.sendCommand(
            "Runtime.evaluate", parameters: ["expression": "6 * 7", "returnByValue": true])
        XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? Int, 42)
    }

    func testRapidReconnectionBindsToAFrontendThatCanStillRunCommands() async throws {
        let page = try await disposablePage()
        let connection = BrowserWebInspectorProtocolConnection(webView: page)
        try await connection.connect()
        defer { connection.disconnect() }
        for attempt in 1...3 {
            connection.disconnect()
            try await connection.connect()
            let response = try await connection.sendCommand(
                "Runtime.evaluate", parameters: ["expression": "6 * 7", "returnByValue": true])
            XCTAssertEqual(
                (response["result"] as? [String: Any])?["value"] as? Int, 42,
                "Reattaching immediately must reach a frontend that still runs commands: attempt \(attempt).")
        }
        connection.disconnect()
        // The extension debugger builds a connection per attach, so a
        // replacement object meets the same half-closed frontend.
        let replacement = BrowserWebInspectorProtocolConnection(webView: page)
        try await replacement.connect()
        defer { replacement.disconnect() }
        let response = try await replacement.sendCommand(
            "Runtime.evaluate", parameters: ["expression": "document.title", "returnByValue": true])
        XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? String, "Crest inspector probe")
    }

    private func waitUntil(_ ready: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while ContinuousClock.now < deadline {
            if try await ready() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(
            domain: "CrestInspectorProbe", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Inspector protocol did not become ready within eight seconds."
            ])
    }

    private func disposablePage() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences)
        let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        page.isInspectable = true
        page.loadHTMLString("<!doctype html><title>Crest inspector probe</title>", baseURL: nil)
        try await waitUntil {
            (try? await page.evaluateJavaScript("document.title")) as? String == "Crest inspector probe"
        }
        return page
    }
}
