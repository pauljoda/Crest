import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeDebuggerDOMSnapshotTests: XCTestCase {
    func testSnapshotFramesAndAccessibilityShareResolvableNodeIDs() async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make(
            html: """
                <!doctype html><title>Main snapshot</title><button id="target">Snapshot target</button>
                <iframe srcdoc="<!doctype html><title>Child snapshot</title><button>Child target</button>"></iframe>
                """, hosted: true, navigable: true)
        defer { fixture.tearDown() }
        let dom = BrowserChromeDebuggerDOM(connection: fixture.connection)
        let accessibility = BrowserChromeDebuggerAccessibility(connection: fixture.connection, dom: dom)
        let snapshot = BrowserChromeDebuggerDOMSnapshot(connection: fixture.connection, dom: dom, webView: fixture.page)
        fixture.route([dom.receive])
        let result = try await snapshot.capture([
            "computedStyles": [], "includePaintOrder": false, "includeDOMRects": false,
        ])
        let documents = try XCTUnwrap(result["documents"] as? [[String: Any]])
        let strings = try XCTUnwrap(result["strings"] as? [String])
        XCTAssertEqual(documents.count, 2)
        XCTAssertTrue(strings.contains("Child target"))
        XCTAssertEqual(strings[try XCTUnwrap(documents[1]["title"] as? Int)], "Child snapshot")
        let nodes = try XCTUnwrap(documents[0]["nodes"] as? [String: Any])
        let childIndexes = try XCTUnwrap(nodes["contentDocumentIndex"] as? [String: [Int]])
        XCTAssertEqual(childIndexes["value"], [1])
        let attributes = try XCTUnwrap(nodes["attributes"] as? [[Int]])
        let target = try XCTUnwrap(
            attributes.firstIndex { values in
                stride(from: 0, to: values.count, by: 2).contains {
                    strings[values[$0]] == "id" && strings[values[$0 + 1]] == "target"
                }
            })
        let backend = try XCTUnwrap((nodes["backendNodeId"] as? [Int])?[target])
        let resolved = try await dom.resolveNode(["backendNodeId": backend])
        let object = try XCTUnwrap((resolved["object"] as? [String: Any])?["objectId"] as? String)
        let text = try await fixture.connection.sendCommand(
            "Runtime.callFunctionOn",
            parameters: [
                "objectId": object, "functionDeclaration": "function() { return this.textContent; }",
                "returnByValue": true,
            ])
        XCTAssertEqual((text["result"] as? [String: Any])?["value"] as? String, "Snapshot target")
        _ = try await accessibility.execute("Accessibility.enable", parameters: [:])
        let tree = try await accessibility.execute("Accessibility.getFullAXTree", parameters: [:])
        let accessible = try XCTUnwrap(
            (tree["nodes"] as? [[String: Any]])?.first {
                ($0["name"] as? [String: Any])?["value"] as? String == "Snapshot target"
            })
        XCTAssertEqual(accessible["backendDOMNodeId"] as? Int, backend)
        let types = try XCTUnwrap(nodes["nodeType"] as? [Int])
        let values = try XCTUnwrap(nodes["nodeValue"] as? [Int])
        let whitespace = try XCTUnwrap(
            types.indices.first {
                types[$0] == 3 && strings[values[$0]].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        let whitespaceID = try XCTUnwrap((nodes["backendNodeId"] as? [Int])?[whitespace])
        let whitespaceObject = try await dom.resolveNode(["backendNodeId": whitespaceID])
        let whitespaceText = try await fixture.connection.sendCommand(
            "Runtime.callFunctionOn",
            parameters: [
                "objectId": try XCTUnwrap((whitespaceObject["object"] as? [String: Any])?["objectId"]),
                "functionDeclaration": "function() { return this.nodeValue; }", "returnByValue": true,
            ])
        XCTAssertEqual((whitespaceText["result"] as? [String: Any])?["value"] as? String, strings[values[whitespace]])
        let repeated = try await snapshot.capture(["computedStyles": []])
        let repeatedNodes = (repeated["documents"] as? [[String: Any]])?.first?["nodes"] as? [String: Any]
        XCTAssertEqual((repeatedNodes?["backendNodeId"] as? [Int])?[whitespace], whitespaceID)
        for context in try await fixture.connection.snapshotContexts(worldName: "Crest Debugger DOM Snapshot") {
            let count = try await fixture.connection.sendCommand(
                "Runtime.evaluate",
                parameters: [
                    "contextId": try XCTUnwrap(context["id"]), "expression": "globalThis.__crestDebuggerSnapshots.size",
                    "returnByValue": true,
                ])
            XCTAssertEqual((count["result"] as? [String: Any])?["value"] as? Int, 0)
        }
        let generation = dom.generation
        let next = try fixture.writePage(named: "next.html", html: "<!doctype html><title>After snapshot</title>")
        fixture.page.loadFileURL(next, allowingReadAccessTo: next.deletingLastPathComponent())
        try await BrowserChromeDebuggerDomainFixture.waitFor { dom.generation > generation }
        for stale in [backend, whitespaceID] {
            do {
                _ = try await dom.resolveNode(["backendNodeId": stale])
                XCTFail("Navigation must invalidate ordinary and whitespace node IDs.")
            } catch BrowserChromeDebuggerProtocolError.invalidParameter("backendNodeId") {}
        }
    }

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

    func testSnapshotWorldReadsClosedShadowRootsAndNativeFrameInfos() async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make(
            html: """
                <!doctype html><div id="host"></div>
                <script>
                document.querySelector('#host').attachShadow({mode:'closed'}).innerHTML='<button>Closed shadow control</button>';
                </script>
                <iframe srcdoc="<!doctype html><title>Child snapshot document</title><button>Frame control</button>"></iframe>
                """, hosted: true)
        defer { fixture.tearDown() }
        let world = try BrowserChromeDebuggerSnapshotWorld.make(name: "Crest closed snapshot fixture")
        let shadowText = try await fixture.page.callAsyncJavaScript(
            "return document.querySelector('#host').shadowRoot.textContent;", arguments: [:], in: nil,
            contentWorld: world)
        XCTAssertEqual(shadowText as? String, "Closed shadow control")
        let original = try await fixture.page.evaluateJavaScript("document.querySelector('#host').shadowRoot === null")
        XCTAssertEqual(original as? Bool, true, "The closed-root capability must remain local to the snapshot world.")
        let frames = try await BrowserChromeDebuggerSnapshotFrames.read(in: fixture.page)
        let info = try XCTUnwrap(frames.dropFirst().first)
        XCTAssertFalse(info.isMainFrame)
        let title = try await fixture.page.callAsyncJavaScript(
            "return document.title;", arguments: [:], in: info, contentWorld: world)
        XCTAssertEqual(title as? String, "Child snapshot document")
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
