import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeDebuggerAccessibilityTests: XCTestCase {
    func testNativeAccessibilityTreeIncludesNamedControlsAndStates() async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make(
            html: """
                <!doctype html><title>Accessible fixture</title>
                <h1>Account settings</h1><button aria-label="Save changes">Save</button>
                <label><input type="checkbox" checked>Notifications</label>
                <p aria-hidden="true">Hidden fixture text</p>
                <input aria-label="Name" value="Fixture name">
                """, hosted: true)
        defer { fixture.tearDown() }
        let dom = BrowserChromeDebuggerDOM(connection: fixture.connection)
        let accessibility = BrowserChromeDebuggerAccessibility(connection: fixture.connection, dom: dom)
        fixture.route([dom.receive])
        _ = try await accessibility.execute("Accessibility.enable", parameters: [:])
        let response = try await accessibility.execute("Accessibility.getFullAXTree", parameters: [:])
        let nodes = try XCTUnwrap(response["nodes"] as? [[String: Any]])
        func named(_ name: String) -> [String: Any]? {
            nodes.first { ($0["name"] as? [String: Any])?["value"] as? String == name }
        }
        let button = try XCTUnwrap(named("Save changes"))
        XCTAssertEqual((button["role"] as? [String: Any])?["value"] as? String, "button")
        XCTAssertEqual((nodes.first?["role"] as? [String: Any])?["value"] as? String, "RootWebArea")
        XCTAssertNotNil(
            nodes.first {
                ($0["role"] as? [String: Any])?["value"] as? String == "StaticText"
                    && ($0["name"] as? [String: Any])?["value"] as? String == "Account settings"
            })
        XCTAssertNil(named("Hidden fixture text"))
        let checkbox = try XCTUnwrap(named("Notifications"))
        let states = try XCTUnwrap(checkbox["properties"] as? [[String: Any]])
        XCTAssertEqual(
            (states.first { $0["name"] as? String == "checked" }?["value"] as? [String: Any])?["value"] as? String,
            "true")
        let again = try await accessibility.execute("Accessibility.getFullAXTree", parameters: [:])
        let next = try XCTUnwrap(again["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.compactMap { $0["nodeId"] as? String }, next.compactMap { $0["nodeId"] as? String })
        let resolved = try await dom.resolveNode(["backendNodeId": try XCTUnwrap(button["backendDOMNodeId"])])
        let objectID = try XCTUnwrap((resolved["object"] as? [String: Any])?["objectId"] as? String)
        let value = try await fixture.connection.sendCommand(
            "Runtime.callFunctionOn",
            parameters: [
                "objectId": objectID, "functionDeclaration": "function() { return this.localName; }",
                "returnByValue": true,
            ])
        XCTAssertEqual((value["result"] as? [String: Any])?["value"] as? String, "button")
    }

    func testNavigationInvalidatesOldNodeIDsAndConcurrentReadsKeepOneDocument() async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make(
            html: "<!doctype html><button>Before navigation</button>", hosted: true, navigable: true)
        defer { fixture.tearDown() }
        let dom = BrowserChromeDebuggerDOM(connection: fixture.connection)
        let accessibility = BrowserChromeDebuggerAccessibility(connection: fixture.connection, dom: dom)
        fixture.route([dom.receive])
        // Independent session commands can arrive before the first document
        // reply. Their roots must share WebKit's single set of node bindings.
        let first = Task { @MainActor in
            try await JSONSerialization.data(
                withJSONObject: accessibility.execute("Accessibility.getFullAXTree", parameters: [:]))
        }
        let second = Task { @MainActor in
            try await JSONSerialization.data(
                withJSONObject: accessibility.execute("Accessibility.getFullAXTree", parameters: [:]))
        }
        let firstData = try await first.value
        let secondData = try await second.value
        let a = try XCTUnwrap(JSONSerialization.jsonObject(with: firstData) as? [String: Any])
        let b = try XCTUnwrap(JSONSerialization.jsonObject(with: secondData) as? [String: Any])
        let firstNodes = try XCTUnwrap(a["nodes"] as? [[String: Any]])
        let secondNodes = try XCTUnwrap(b["nodes"] as? [[String: Any]])
        XCTAssertEqual(
            firstNodes.compactMap { $0["nodeId"] as? String }, secondNodes.compactMap { $0["nodeId"] as? String })
        let oldID = try XCTUnwrap(firstNodes.first?["backendDOMNodeId"])
        let destination = try fixture.writePage(
            named: "next.html", html: "<!doctype html><button>After navigation</button>")
        fixture.page.load(URLRequest(url: destination))
        try await BrowserChromeDebuggerDomainFixture.waitFor {
            fixture.page.url == destination && !fixture.page.isLoading
        }
        let updated = try await accessibility.execute("Accessibility.getFullAXTree", parameters: [:])
        XCTAssertTrue(
            (updated["nodes"] as? [[String: Any]] ?? []).contains {
                ($0["name"] as? [String: Any])?["value"] as? String == "After navigation"
            })
        do {
            _ = try await dom.resolveNode(["backendNodeId": oldID])
            XCTFail("A previous document's node must not resolve into the new page.")
        } catch {
            XCTAssertEqual(error as? BrowserChromeDebuggerProtocolError, .invalidParameter("backendNodeId"))
        }
    }
}
