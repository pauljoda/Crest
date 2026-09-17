import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeDebuggerDOMSnapshotTests: XCTestCase {
    func testSnapshotColumnsMeasureLiveLayoutWithoutPageDefinedGetters() async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make(
            html: """
                <!doctype html><style>body { margin:0 } #target { position:absolute; left:20px; top:30px;
                    width:100px; height:40px; background:rgb(0, 0, 255) }</style>
                <button id="target">Hi😀</button><button id="hidden" style="display:none">Hidden</button>
                <div id="host"></div><script>
                document.querySelector('#host').attachShadow({mode:'closed'}).innerHTML='<span>Closed snapshot text</span>';
                Element.prototype.getBoundingClientRect = function() { throw new Error('Page getter must not run'); };
                window.getComputedStyle = function() { throw new Error('Page style getter must not run'); };
                </script>
                """, hosted: true)
        defer { fixture.tearDown() }
        let world = try BrowserChromeDebuggerSnapshotWorld.make(name: "Crest snapshot columns fixture")
        let result = try await fixture.page.callAsyncJavaScript(
            BrowserChromeDebuggerDOMSnapshotScript.source,
            arguments: ["snapshotKey": "fixture", "computedStyles": ["background-color"]], in: nil, contentWorld: world)
        let snapshot = try XCTUnwrap(result as? [String: Any])
        let strings = try XCTUnwrap(snapshot["strings"] as? [String])
        let document = try XCTUnwrap(snapshot["document"] as? [String: Any])
        let nodes = try XCTUnwrap(document["nodes"] as? [String: Any])
        let attributes = try XCTUnwrap(nodes["attributes"] as? [[Int]])
        func named(_ name: String) -> Int? {
            attributes.firstIndex { values in
                stride(from: 0, to: values.count, by: 2).contains {
                    strings[values[$0]] == "id" && strings[values[$0 + 1]] == name
                }
            }
        }
        let target = try XCTUnwrap(named("target"))
        let layout = try XCTUnwrap(document["layout"] as? [String: Any])
        let nodeIndexes = try XCTUnwrap(layout["nodeIndex"] as? [Int])
        let targetLayout = try XCTUnwrap(nodeIndexes.firstIndex(of: target))
        XCTAssertEqual((layout["bounds"] as? [[Double]])?[targetLayout], [20, 30, 100, 40])
        let styleID = try XCTUnwrap((layout["styles"] as? [[Int]])?[targetLayout].first)
        XCTAssertEqual(strings[styleID], "rgb(0, 0, 255)")
        XCTAssertFalse(nodeIndexes.contains(try XCTUnwrap(named("hidden"))))
        XCTAssertTrue(strings.contains("Closed snapshot text"))
        let boxes = try XCTUnwrap(document["textBoxes"] as? [String: Any])
        XCTAssertTrue(
            (boxes["length"] as? [Int] ?? []).contains(2), "Surrogate pairs retain their UTF-16 range length.")
        let count = try await fixture.page.callAsyncJavaScript(
            "return globalThis.__crestDebuggerSnapshots.get('fixture').length;", arguments: [:], in: nil,
            contentWorld: world)
        XCTAssertEqual(count as? Int, attributes.count)
    }

    func testIsolatedSnapshotWorldCanResolveNativeNodeIdentity() async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make(
            html: "<!doctype html><button>Snapshot control</button>", hosted: true)
        defer { fixture.tearDown() }
        let runtime = BrowserChromeDebuggerRuntime(connection: fixture.connection)
        runtime.onEvent = fixture.recorder()
        fixture.route([runtime.receive])
        _ = try await runtime.execute("Runtime.enable", parameters: [:])
        let name = "Crest snapshot fixture"
        let world = try BrowserChromeDebuggerSnapshotWorld.make(name: name)
        _ = try await fixture.page.callAsyncJavaScript(
            "globalThis.fixtureNode = document.querySelector('button'); return true;", arguments: [:], in: nil,
            contentWorld: world)
        try await BrowserChromeDebuggerDomainFixture.waitFor {
            fixture.all("Runtime.executionContextCreated").contains {
                ($0["context"] as? [String: Any])?["name"] as? String == name
            }
        }
        let context = try XCTUnwrap(
            fixture.all("Runtime.executionContextCreated").compactMap {
                $0["context"] as? [String: Any]
            }.first { $0["name"] as? String == name })
        let response = try await runtime.execute(
            "Runtime.evaluate",
            parameters: [
                "expression": "globalThis.fixtureNode", "contextId": try XCTUnwrap(context["id"]),
                "returnByValue": false,
            ])
        let objectID = try XCTUnwrap((response["result"] as? [String: Any])?["objectId"] as? String)
        let contexts = try await fixture.connection.snapshotContexts(worldName: name)
        XCTAssertTrue(contexts.contains { $0["id"] as? Int == context["id"] as? Int })
        _ = try await fixture.connection.sendCommand("DOM.getDocument")
        let ids = try await fixture.connection.bindSnapshotNodes(objectIDs: [objectID])
        let id = try XCTUnwrap(ids.first)
        let properties = try await fixture.connection.sendCommand(
            "DOM.getAccessibilityPropertiesForNode", parameters: ["nodeId": id])
        XCTAssertEqual((properties["properties"] as? [String: Any])?["label"] as? String, "Snapshot control")
    }

}
