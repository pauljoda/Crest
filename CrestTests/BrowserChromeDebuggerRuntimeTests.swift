import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeDebuggerRuntimeTests: XCTestCase {
    func testCancelledEvaluationDoesNotRunPageCode() async throws {
        try await withRuntime { runtime, _ in
            let evaluation = Task { @MainActor in
                _ = try await runtime.execute(
                    "Runtime.evaluate",
                    parameters: [
                        "expression": "globalThis.crestCancelledEvaluation = true"
                    ])
            }
            evaluation.cancel()
            do {
                _ = try await evaluation.value
                XCTFail("An already cancelled command must not execute.")
            } catch is CancellationError {} catch {
                XCTFail("Expected cancellation, not \(error)")
            }
            let result = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": "typeof globalThis.crestCancelledEvaluation"
                ])
            XCTAssertEqual((result["result"] as? [String: Any])?["value"] as? String, "undefined")
        }
    }

    func testRuntimeEnableRebindsAfterTheInspectorConnectionIsReplaced() async throws {
        try await withRuntime { runtime, connection in
            var contexts: [[String: Any]] = []
            runtime.onEvent = { method, parameters in
                if method == "Runtime.executionContextCreated", let context = parameters["context"] as? [String: Any] {
                    contexts.append(context)
                }
            }
            _ = try await runtime.execute("Runtime.enable", parameters: [:])
            try await self.waitUntil { !contexts.isEmpty }
            connection.disconnect()
            contexts.removeAll()
            try await connection.connect()
            _ = try await runtime.execute("Runtime.enable", parameters: [:])
            try await self.waitUntil { !contexts.isEmpty }
            XCTAssertNotNil(contexts.first?["id"] as? Int)
        }
    }

    func testNavigationDestroysTheOldContextAndReportsAnEvaluableReplacement() async throws {
        try await withRuntimePage { runtime, _, page in
            var created: [[String: Any]] = []
            var destroyed: [Int] = []
            runtime.onEvent = { method, parameters in
                if method == "Runtime.executionContextCreated", let context = parameters["context"] as? [String: Any] {
                    created.append(context)
                }
                if method == "Runtime.executionContextDestroyed", let id = parameters["executionContextId"] as? Int {
                    destroyed.append(id)
                }
            }
            _ = try await runtime.execute("Runtime.enable", parameters: [:])
            try await self.waitUntil { !created.isEmpty }
            let oldContext = try XCTUnwrap(created.first)
            let oldID = try XCTUnwrap(oldContext["id"] as? Int)
            page.loadHTMLString("<!doctype html><title>Replacement context</title>", baseURL: nil)
            try await self.waitUntil { destroyed.contains(oldID) && created.contains { $0["id"] as? Int != oldID } }
            let replacement = try XCTUnwrap(created.last { $0["id"] as? Int != oldID })
            let newID = try XCTUnwrap(replacement["id"] as? Int)
            XCTAssertNotEqual(replacement["uniqueId"] as? String, oldContext["uniqueId"] as? String)
            let result = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": "document.title", "contextId": newID,
                ])
            XCTAssertEqual((result["result"] as? [String: Any])?["value"] as? String, "Replacement context")
            do {
                _ = try await runtime.execute(
                    "Runtime.evaluate", parameters: ["expression": "document.title", "contextId": oldID])
                XCTFail("A destroyed context must not silently evaluate in the replacement page.")
            } catch {}
        }
    }

    func testEvaluationReturnsChromeValuesAndExceptionDetails() async throws {
        try await withRuntime { runtime, _ in
            let value = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": "({answer: 42})", "returnByValue": true,
                ])
            let object = try XCTUnwrap(value["result"] as? [String: Any])
            XCTAssertEqual((object["value"] as? [String: Int])?["answer"], 42)
            XCTAssertNil(value["wasThrown"])
            let failure = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": "throw new Error('crest-protocol-failure')", "silent": true,
                ])
            XCTAssertNil(failure["wasThrown"])
            let details = try XCTUnwrap(failure["exceptionDetails"] as? [String: Any])
            XCTAssertNotNil(details["exceptionId"] as? Int)
            XCTAssertTrue(
                (details["exception"] as? [String: Any])?["description"] as? String == "Error: crest-protocol-failure")
        }
    }

    func testObjectPropertiesFunctionCallsAndReleaseUseTheRealRemoteObject() async throws {
        try await withRuntime { runtime, _ in
            let value = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": "({answer: 40})", "objectGroup": "crest-runtime-test",
                ])
            let objectID = try XCTUnwrap((value["result"] as? [String: Any])?["objectId"] as? String)
            let properties = try await runtime.execute(
                "Runtime.getProperties",
                parameters: [
                    "objectId": objectID, "ownProperties": true,
                ])
            let entries = try XCTUnwrap(properties["result"] as? [[String: Any]])
            XCTAssertEqual(
                (entries.first { $0["name"] as? String == "answer" }?["value"] as? [String: Any])?["value"] as? Int, 40)
            XCTAssertNil(properties["properties"])
            let call = try await runtime.execute(
                "Runtime.callFunctionOn",
                parameters: [
                    "objectId": objectID, "functionDeclaration": "function(n) { return this.answer + n; }",
                    "arguments": [["value": 2]], "returnByValue": true,
                ])
            XCTAssertEqual((call["result"] as? [String: Any])?["value"] as? Int, 42)
            _ = try await runtime.execute(
                "Runtime.releaseObjectGroup", parameters: ["objectGroup": "crest-runtime-test"])
            do {
                _ = try await runtime.execute("Runtime.getProperties", parameters: ["objectId": objectID])
                XCTFail("Released remote objects must no longer be usable.")
            } catch {}
        }
    }

    func testUnsupportedEvaluationConstraintsRejectBeforeExecutingTheExpression() async throws {
        try await withRuntime { runtime, _ in
            for parameter in ["throwOnSideEffect", "disableBreaks"] {
                do {
                    _ = try await runtime.execute(
                        "Runtime.evaluate",
                        parameters: [
                            "expression": "globalThis.crestUnexpectedEvaluation = true", parameter: true,
                        ])
                    XCTFail("An unsupported execution constraint must not be ignored: \(parameter)")
                } catch {}
            }
            let value = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": "typeof globalThis.crestUnexpectedEvaluation", "returnByValue": true,
                ])
            XCTAssertEqual((value["result"] as? [String: Any])?["value"] as? String, "undefined")
        }
    }

    func testEvaluationTimeoutBoundsAnUnsettledPromiseAndReportsEngineLimitation() async throws {
        try await withRuntime { runtime, _ in
            do {
                _ = try await runtime.execute(
                    "Runtime.evaluate",
                    parameters: [
                        "expression": "new Promise(() => {})", "awaitPromise": true, "timeout": 100,
                    ])
                XCTFail("An unsettled promise must time out.")
            } catch {
                XCTAssertTrue(String(describing: error).contains("WebKit cannot terminate"))
            }
            let value = try await runtime.execute("Runtime.evaluate", parameters: ["expression": "6 * 7"])
            XCTAssertEqual((value["result"] as? [String: Any])?["value"] as? Int, 42)
        }
    }

    func testNonJSONNumbersAndBigIntegersRetainTheirChromeRepresentation() async throws {
        try await withRuntime { runtime, _ in
            for expression in ["NaN", "Infinity", "-Infinity", "-0", "12345678901234567890n"] {
                let response = try await runtime.execute("Runtime.evaluate", parameters: ["expression": expression])
                let remote = try XCTUnwrap(response["result"] as? [String: Any])
                XCTAssertEqual(remote["unserializableValue"] as? String, expression)
                XCTAssertNil(remote["value"])
            }
        }
    }

    private func withRuntime(
        _ operation: (BrowserChromeDebuggerRuntime, BrowserWebInspectorProtocolConnection) async throws -> Void
    ) async throws {
        try await withRuntimePage { runtime, connection, _ in
            try await operation(runtime, connection)
        }
    }

    private func withRuntimePage(
        _ operation: (BrowserChromeDebuggerRuntime, BrowserWebInspectorProtocolConnection, WKWebView) async throws ->
            Void
    ) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences)
        let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        page.isInspectable = true
        page.loadHTMLString("<!doctype html><title>Crest runtime test</title>", baseURL: nil)
        defer { page.stopLoading() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (try? await page.evaluateJavaScript("document.title")) as? String != "Crest runtime test" {
            guard ContinuousClock.now < deadline else { throw BrowserWebInspectorProtocolError.timedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
        let connection = BrowserWebInspectorProtocolConnection(webView: page)
        try await connection.connect()
        defer { connection.disconnect() }
        let runtime = BrowserChromeDebuggerRuntime(connection: connection)
        connection.onEvent = { [weak runtime] method, parameters in
            runtime?.receive(method, parameters: parameters)
        }
        try await operation(runtime, connection, page)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw BrowserWebInspectorProtocolError.timedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
