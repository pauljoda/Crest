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

    func testRepeatedRuntimeEnableRejectsAfterDisconnection() async throws {
        try await withRuntime { runtime, connection in
            _ = try await runtime.execute("Runtime.enable", parameters: [:])
            connection.disconnect()
            do {
                _ = try await runtime.execute("Runtime.enable", parameters: [:])
                XCTFail("An enabled subscription must not hide a disconnected engine.")
            } catch BrowserWebInspectorProtocolError.notConnected {}
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

    func testRuntimeEnableReportsTheExistingContextWithoutRestartingTheEngineDomain() async throws {
        try await withRuntime { runtime, _ in
            let received = self.expectation(description: "Existing page execution context")
            var contexts: [[String: Any]] = []
            runtime.onEvent = { method, parameters in
                guard method == "Runtime.executionContextCreated",
                    let context = parameters["context"] as? [String: Any]
                else { return }
                contexts.append(context)
                if (context["auxData"] as? [String: Any])?["isDefault"] as? Bool == true {
                    received.fulfill()
                }
            }
            _ = try await runtime.execute("Runtime.enable", parameters: [:])
            await self.fulfillment(of: [received], timeout: 5)
            let context = try XCTUnwrap(
                contexts.first {
                    ($0["auxData"] as? [String: Any])?["isDefault"] as? Bool == true
                })
            let id = try XCTUnwrap(context["id"] as? Int)
            XCTAssertFalse(try XCTUnwrap(context["uniqueId"] as? String).isEmpty)
            XCTAssertNotNil(context["origin"] as? String)
            XCTAssertNotNil((context["auxData"] as? [String: Any])?["frameId"] as? String)
            let evaluated = try await runtime.execute(
                "Runtime.evaluate", parameters: ["expression": "document.title", "contextId": id])
            XCTAssertEqual((evaluated["result"] as? [String: Any])?["value"] as? String, "Crest runtime test")
            let count = contexts.count
            _ = try await runtime.execute("Runtime.enable", parameters: [:])
            _ = try await runtime.execute("Runtime.evaluate", parameters: ["expression": "0"])
            XCTAssertEqual(contexts.count, count, "Repeated enable must not duplicate existing contexts.")
        }
    }

    func testRuntimeTracksAnIframeContextAndItsRemoval() async throws {
        try await withRuntime { runtime, _ in
            var created: [[String: Any]] = []
            var destroyed: [[String: Any]] = []
            runtime.onEvent = { method, parameters in
                if method == "Runtime.executionContextCreated", let context = parameters["context"] as? [String: Any] {
                    created.append(context)
                }
                if method == "Runtime.executionContextDestroyed" { destroyed.append(parameters) }
            }
            _ = try await runtime.execute("Runtime.enable", parameters: [:])
            try await self.waitUntil { !created.isEmpty }
            let initialIDs = Set(created.compactMap { $0["id"] as? Int })
            _ = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": """
                    globalThis.crestTestFrame = document.createElement('iframe');
                    crestTestFrame.srcdoc = '<!doctype html><title>Child context</title>';
                    document.body.append(crestTestFrame); undefined;
                    """
                ])
            try await self.waitUntil { created.contains { !initialIDs.contains($0["id"] as? Int ?? -1) } }
            let child = try XCTUnwrap(created.last { !initialIDs.contains($0["id"] as? Int ?? -1) })
            let childID = try XCTUnwrap(child["id"] as? Int)
            let value = try await runtime.execute(
                "Runtime.evaluate", parameters: ["expression": "document.title", "contextId": childID])
            XCTAssertEqual((value["result"] as? [String: Any])?["value"] as? String, "Child context")
            _ = try await runtime.execute("Runtime.evaluate", parameters: ["expression": "crestTestFrame.remove()"])
            try await self.waitUntil { destroyed.contains { $0["executionContextId"] as? Int == childID } }
            XCTAssertEqual(
                destroyed.first { $0["executionContextId"] as? Int == childID }?["executionContextUniqueId"] as? String,
                child["uniqueId"] as? String)
            XCTAssertFalse(destroyed.contains { initialIDs.contains($0["executionContextId"] as? Int ?? -1) })
        }
    }

    func testRuntimeDisableStopsEventsAndReenableSnapshotsCurrentContexts() async throws {
        try await withRuntime { runtime, _ in
            var contexts: [[String: Any]] = []
            runtime.onEvent = { method, parameters in
                if method == "Runtime.executionContextCreated", let context = parameters["context"] as? [String: Any] {
                    contexts.append(context)
                }
            }
            _ = try await runtime.execute("Runtime.enable", parameters: [:])
            try await self.waitUntil { !contexts.isEmpty }
            let initial = try XCTUnwrap(contexts.first)
            _ = try await runtime.execute("Runtime.disable", parameters: [:])
            contexts.removeAll()
            _ = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": """
                    new Promise(resolve => {
                        const frame = document.createElement('iframe');
                        frame.onload = () => resolve();
                        frame.srcdoc = '<!doctype html><title>Created while disabled</title>';
                        document.body.append(frame);
                    })
                    """, "awaitPromise": true,
                ])
            XCTAssertTrue(contexts.isEmpty)
            _ = try await runtime.execute("Runtime.enable", parameters: [:])
            try await self.waitUntil { contexts.count >= 2 }
            XCTAssertEqual(
                contexts.first { $0["id"] as? Int == initial["id"] as? Int }?["uniqueId"] as? String,
                initial["uniqueId"] as? String,
                "The same live context keeps its unique identity across event subscriptions.")
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

    func testEvaluationAwaitsBothResolvedAndRejectedPromises() async throws {
        try await withRuntime { runtime, _ in
            let value = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": "Promise.resolve({answer: 42})", "awaitPromise": true, "returnByValue": true,
                ])
            XCTAssertEqual(((value["result"] as? [String: Any])?["value"] as? [String: Int])?["answer"], 42)
            let failure = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": "Promise.reject(new Error('crest-promise-failure'))", "awaitPromise": true,
                ])
            XCTAssertNotNil(failure["exceptionDetails"])
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
            for parameter in ["throwOnSideEffect", "replMode", "disableBreaks"] {
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

    func testFunctionCanTargetAnActualExecutionContext() async throws {
        try await withRuntime { runtime, connection in
            let received = self.expectation(description: "Default execution context")
            var contextID: Int?
            connection.onEvent = { method, parameters in
                guard method == "Runtime.executionContextCreated", contextID == nil,
                    let context = parameters["context"] as? [String: Any],
                    context["type"] as? String == "normal", let id = context["id"] as? Int
                else { return }
                contextID = id
                received.fulfill()
            }
            // Inspector bootstrap already enabled Runtime. Start a fresh
            // listener interval so the engine publishes its real context ID.
            _ = try await connection.sendCommand("Runtime.disable")
            _ = try await connection.sendCommand("Runtime.enable")
            await self.fulfillment(of: [received], timeout: 5)
            let id = try XCTUnwrap(contextID)
            let response = try await runtime.execute(
                "Runtime.callFunctionOn",
                parameters: [
                    "executionContextId": id,
                    "functionDeclaration": "function() { return this === globalThis ? 42 : 0; }",
                    "returnByValue": true, "objectGroup": "crest-context-test",
                ])
            XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? Int, 42)
            _ = try await runtime.execute(
                "Runtime.releaseObjectGroup", parameters: ["objectGroup": "crest-context-test"])
        }
    }

    func testUnsupportedCallArgumentsRejectBeforeTheFunctionRuns() async throws {
        try await withRuntime { runtime, _ in
            let value = try await runtime.execute("Runtime.evaluate", parameters: ["expression": "globalThis"])
            let objectID = try XCTUnwrap((value["result"] as? [String: Any])?["objectId"] as? String)
            do {
                _ = try await runtime.execute(
                    "Runtime.callFunctionOn",
                    parameters: [
                        "objectId": objectID,
                        "functionDeclaration": "function() { globalThis.crestUnexpectedCall = true; }",
                        "arguments": [["unserializableValue": "not-a-number-literal"]],
                    ])
                XCTFail("An unsupported argument must not silently turn into undefined.")
            } catch {}
            let response = try await runtime.execute(
                "Runtime.evaluate",
                parameters: [
                    "expression": "typeof globalThis.crestUnexpectedCall", "returnByValue": true,
                ])
            XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? String, "undefined")
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
