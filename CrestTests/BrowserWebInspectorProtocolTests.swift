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

    func testConnectionReceivesActualEngineEvents() async throws {
        let page = try await disposablePage()
        let connection = BrowserWebInspectorProtocolConnection(webView: page)
        let received = expectation(description: "Engine console event")
        var didReceive = false
        connection.onEvent = { method, parameters in
            guard method == "Console.messageAdded",
                let message = parameters["message"] as? [String: Any],
                message["text"] as? String == "crest-engine-event", !didReceive
            else { return }
            didReceive = true
            received.fulfill()
        }
        try await connection.connect()
        defer { connection.disconnect() }
        _ = try await connection.sendCommand("Console.enable")
        _ = try await page.evaluateJavaScript("console.log('crest-engine-event')")
        await fulfillment(of: [received], timeout: 5)
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

    func testUnsupportedEngineParametersRejectBeforeCommandExecution() async throws {
        let page = try await disposablePage()
        let connection = BrowserWebInspectorProtocolConnection(webView: page)
        try await connection.connect()
        defer { connection.disconnect() }
        do {
            _ = try await connection.sendCommand(
                "Runtime.evaluate",
                parameters: [
                    "expression": "globalThis.crestIgnoredParameter = true", "crestUnsupportedSafetyConstraint": true,
                ])
            XCTFail("WebKit's argument filtering must not silently discard requested behavior.")
        } catch {}
        let response = try await connection.sendCommand(
            "Runtime.evaluate",
            parameters: [
                "expression": "typeof globalThis.crestIgnoredParameter", "returnByValue": true,
            ])
        XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? String, "undefined")
    }

    func testHiddenInspectorCanExecuteACommandInItsOwnPage() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        XCTAssertTrue(BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences))
        let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        page.isInspectable = true
        page.loadHTMLString("<!doctype html><title>Crest inspector probe</title><p>Disposable page</p>", baseURL: nil)
        defer { page.stopLoading() }

        try await waitUntil {
            (try? await page.evaluateJavaScript("document.title")) as? String == "Crest inspector probe"
        }
        let inspectorSelector = NSSelectorFromString("_inspector")
        XCTAssertTrue(page.responds(to: inspectorSelector))
        let inspector = try XCTUnwrap(page.perform(inspectorSelector)?.takeUnretainedValue() as? NSObject)
        let connect = NSSelectorFromString("connect")
        let close = NSSelectorFromString("close")
        let frontendSelector = NSSelectorFromString("inspectorWebView")
        XCTAssertTrue(inspector.responds(to: connect))
        XCTAssertTrue(inspector.responds(to: close))
        XCTAssertTrue(inspector.responds(to: frontendSelector))
        inspector.perform(connect)
        defer { inspector.perform(close) }

        var frontend: WKWebView?
        try await waitUntil {
            frontend = inspector.perform(frontendSelector)?.takeUnretainedValue() as? WKWebView
            guard let frontend else { return false }
            return
                (try? await frontend.evaluateJavaScript(
                    "typeof InspectorBackend !== 'undefined' && !!globalThis.WI?.pageTarget?.RuntimeAgent"
                )) as? Bool == true
        }

        let result = try await XCTUnwrap(frontend).callAsyncJavaScript(
            """
            const target = WI.pageTarget;
            const response = await InspectorBackend.invokeCommand(
                'Runtime.evaluate', target.type, target.connection,
                {expression: 'document.title', returnByValue: true}
            );
            const commands = [
                'Runtime.evaluate', 'Runtime.enable', 'Network.enable', 'Page.enable',
                'Page.captureScreenshot', 'Page.snapshotRect', 'Page.handleJavaScriptDialog',
                'Input.dispatchMouseEvent', 'Input.dispatchKeyEvent', 'Input.insertText',
                'DOM.getDocument', 'Target.getTargets'
            ];
            return JSON.stringify({response, commands: Object.fromEntries(
                commands.map(name => [name, InspectorBackend.hasCommand(name)])
            )});
            """, arguments: [:], contentWorld: .page)
        let json = try XCTUnwrap(result as? String)
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let commandResponse = try XCTUnwrap(response["response"] as? [String: Any])
        let remoteValue = try XCTUnwrap(commandResponse["result"] as? [String: Any])
        XCTAssertEqual(remoteValue["value"] as? String, "Crest inspector probe")
        print("CREST_INSPECTOR_PROTOCOL_PROBE \(json)")

        let visible = NSSelectorFromString("isVisible")
        let getter = unsafeBitCast(
            inspector.method(for: visible),
            to: (@convention(c) (AnyObject, Selector) -> Bool).self
        )
        XCTAssertFalse(getter(inspector, visible), "The engine connection must not open Inspector UI.")
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
