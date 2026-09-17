import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeDebuggerConsoleTests: XCTestCase {
    func testConsoleCallsArriveAsChromeEventsWithTranslatedArguments() async throws {
        try await withConsole { console, fixture in
            _ = try await fixture.page.evaluateJavaScript(
                "console.log('crest-console', 42, {answer: 42}); undefined")
            try await fixture.waitForEvent("Runtime.consoleAPICalled") { parameters in
                (parameters["args"] as? [[String: Any]])?.first?["value"] as? String == "crest-console"
            }
            let call = try XCTUnwrap(
                fixture.all("Runtime.consoleAPICalled").first {
                    ($0["args"] as? [[String: Any]])?.first?["value"] as? String == "crest-console"
                })
            XCTAssertEqual(call["type"] as? String, "log")
            let args = try XCTUnwrap(call["args"] as? [[String: Any]])
            XCTAssertEqual(args.count, 3)
            XCTAssertEqual(args[1]["value"] as? Int, 42)
            XCTAssertEqual(args[2]["type"] as? String, "object")
            XCTAssertNotNil(args[2]["objectId"] as? String)
            let contextID = try XCTUnwrap(call["executionContextId"] as? Int)
            XCTAssertGreaterThan(contextID, 0)
            XCTAssertGreaterThan(try XCTUnwrap(call["timestamp"] as? Double), 0)
        }
    }

    func testUncaughtErrorsBecomeExceptionThrownWithDetails() async throws {
        try await withConsole { console, fixture in
            _ = try await fixture.page.evaluateJavaScript(
                "setTimeout(() => { throw new Error('crest-uncaught'); }, 0); undefined")
            try await fixture.waitForEvent("Runtime.exceptionThrown")
            let event = try XCTUnwrap(fixture.first("Runtime.exceptionThrown"))
            XCTAssertGreaterThan(try XCTUnwrap(event["timestamp"] as? Double), 0)
            let details = try XCTUnwrap(event["exceptionDetails"] as? [String: Any])
            XCTAssertGreaterThan(try XCTUnwrap(details["exceptionId"] as? Int), 0)
            XCTAssertTrue(try XCTUnwrap(details["text"] as? String).contains("crest-uncaught"))
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(details["lineNumber"] as? Int), 0)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(details["columnNumber"] as? Int), 0)
            let trace = try XCTUnwrap(details["stackTrace"] as? [String: Any])
            let frames = try XCTUnwrap(trace["callFrames"] as? [[String: Any]])
            XCTAssertFalse(frames.isEmpty)
            XCTAssertNotNil(frames[0]["url"] as? String)
            XCTAssertTrue(frames[0]["scriptId"] is String)
        }
    }

    private func withConsole(
        _ operation: (BrowserChromeDebuggerConsole, BrowserChromeDebuggerDomainFixture) async throws -> Void
    ) async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make()
        defer { fixture.tearDown() }
        let console = BrowserChromeDebuggerConsole(connection: fixture.connection)
        console.onEvent = fixture.recorder()
        fixture.route([{ [weak console] method, parameters in console?.receive(method, parameters: parameters) }])
        try await console.enable()
        try await operation(console, fixture)
    }
}
