import WebKit
import XCTest

@testable import Crest

/// The session store is what a client actually talks to, so the domains have to
/// be reachable through it: a translator that only works when constructed by
/// hand is a translator no extension can use.
@MainActor
final class BrowserExtensionDebuggerSessionDomainRoutingTests: XCTestCase {
    func testFetchRequestPauseAndContinueUseStableRequestIdentity() async throws {
        try await withSession { store, page, target, client in
            let events = EventRecorder()
            let stream = Task { @MainActor in
                for await event in store.events(for: client) { events.values.append(event) }
            }
            defer { stream.cancel() }
            _ = try await self.send("Fetch.enable", [:], store: store, target: target, client: client)
            _ = try await page.evaluateJavaScript(
                """
                globalThis.fetchResult = 'pending';
                fetch('https://crest.invalid/fetch-request').then(
                    () => { fetchResult = 'finished'; }, () => { fetchResult = 'failed'; });
                undefined
                """)
            try await BrowserChromeDebuggerDomainFixture.waitFor {
                events.method("Fetch.requestPaused") { $0["responseStatusCode"] == nil }
            }
            let paused = try XCTUnwrap(events.parameters("Fetch.requestPaused").first)
            let requestID = try XCTUnwrap(paused["requestId"] as? String)
            XCTAssertFalse(requestID.isEmpty)
            XCTAssertFalse(try XCTUnwrap(paused["frameId"] as? String).isEmpty)
            XCTAssertEqual(paused["resourceType"] as? String, "Fetch")
            XCTAssertNotNil(paused["networkId"] as? String)
            let before = try await page.evaluateJavaScript("fetchResult") as? String
            XCTAssertEqual(before, "pending")
            _ = try await self.send(
                "Fetch.continueRequest", ["requestId": requestID], store: store, target: target, client: client)
            try await BrowserChromeDebuggerDomainFixture.waitFor {
                (try await page.evaluateJavaScript("fetchResult")) as? String != "pending"
            }
            do {
                _ = try await self.send(
                    "Fetch.continueRequest", ["requestId": requestID], store: store, target: target, client: client)
                XCTFail("A completed pause ID must not be reusable.")
            } catch {}
            _ = try await self.send("Fetch.disable", [:], store: store, target: target, client: client)
        }
    }

    func testFetchResponsePatternPausesAndDisableReleasesTheBody() async throws {
        try await withSession { store, page, target, client in
            let events = EventRecorder()
            let stream = Task { @MainActor in
                for await event in store.events(for: client) { events.values.append(event) }
            }
            defer { stream.cancel() }
            _ = try await self.send(
                "Fetch.enable",
                ["patterns": [["urlPattern": "blob:*", "resourceType": "Fetch", "requestStage": "Response"]]],
                store: store, target: target, client: client)
            _ = try await page.evaluateJavaScript(
                """
                globalThis.fetchResult = 'pending';
                const url = URL.createObjectURL(new Blob(['fetch-response-body'], {type: 'text/plain'}));
                fetch(url).then(response => response.text()).then(text => { fetchResult = text; });
                undefined
                """)
            try await BrowserChromeDebuggerDomainFixture.waitFor {
                events.method("Fetch.requestPaused") { $0["responseStatusCode"] as? Int == 200 }
            }
            let paused = try XCTUnwrap(events.parameters("Fetch.requestPaused").first)
            XCTAssertEqual(paused["resourceType"] as? String, "Fetch")
            XCTAssertNotNil(paused["responseHeaders"] as? [[String: String]])
            XCTAssertEqual((paused["request"] as? [String: Any])?["method"] as? String, "GET")
            let before = try await page.evaluateJavaScript("fetchResult") as? String
            XCTAssertEqual(before, "pending")
            _ = try await self.send("Fetch.disable", [:], store: store, target: target, client: client)
            try await BrowserChromeDebuggerDomainFixture.waitFor {
                (try await page.evaluateJavaScript("fetchResult")) as? String == "fetch-response-body"
            }
        }
    }

    func testFetchEmptyPatternsAndUnsupportedAuthenticationAreExplicit() async throws {
        try await withSession { store, page, target, client in
            _ = try await self.send(
                "Fetch.enable", ["patterns": [], "handleAuthRequests": false], store: store, target: target,
                client: client)
            do {
                _ = try await self.send(
                    "Fetch.enable", ["handleAuthRequests": true], store: store, target: target, client: client)
                XCTFail("WebKit has no Fetch authentication challenge interception.")
            } catch BrowserChromeDebuggerProtocolError.unsupportedParameter("handleAuthRequests") {}
            _ = try await page.evaluateJavaScript(
                "globalThis.fetchResult = 'pending'; fetch('https://crest.invalid/no-interception').catch(() => { fetchResult = 'failed'; }); undefined"
            )
            try await BrowserChromeDebuggerDomainFixture.waitFor {
                (try await page.evaluateJavaScript("fetchResult")) as? String == "failed"
            }
            _ = try await self.send("Fetch.disable", [:], store: store, target: target, client: client)
        }
    }

    func testFetchCanFulfillOrFailAPausedRequest() async throws {
        for fulfill in [true, false] {
            try await withSession { store, page, target, client in
                let events = EventRecorder()
                let stream = Task { @MainActor in
                    for await event in store.events(for: client) { events.values.append(event) }
                }
                defer { stream.cancel() }
                _ = try await self.send("Fetch.enable", [:], store: store, target: target, client: client)
                _ = try await page.evaluateJavaScript(
                    """
                    globalThis.fetchResult = 'pending';
                    fetch('https://crest.invalid/fulfill').then(response => response.text()).then(
                        text => { fetchResult = text; }, () => { fetchResult = 'failed'; });
                    undefined
                    """)
                try await BrowserChromeDebuggerDomainFixture.waitFor {
                    !events.parameters("Fetch.requestPaused").isEmpty
                }
                let paused = try XCTUnwrap(events.parameters("Fetch.requestPaused").first)
                let requestID = try XCTUnwrap(paused["requestId"] as? String)
                if fulfill {
                    _ = try await self.send(
                        "Fetch.fulfillRequest",
                        [
                            "requestId": requestID, "responseCode": 200,
                            "body": Data("fetch-fulfilled".utf8).base64EncodedString(),
                            "responseHeaders": [
                                ["name": "Content-Type", "value": "text/plain"],
                                ["name": "Access-Control-Allow-Origin", "value": "*"],
                            ],
                        ], store: store, target: target, client: client)
                } else {
                    _ = try await self.send(
                        "Fetch.failRequest", ["requestId": requestID, "errorReason": "Aborted"], store: store,
                        target: target, client: client)
                }
                try await BrowserChromeDebuggerDomainFixture.waitFor {
                    (try await page.evaluateJavaScript("fetchResult")) as? String
                        == (fulfill ? "fetch-fulfilled" : "failed")
                }
            }
        }
    }

    func testFetchDocumentResponseFilterLetsOtherResourcesFinish() async throws {
        try await withSession { store, page, target, client in
            let events = EventRecorder()
            let stream = Task { @MainActor in
                for await event in store.events(for: client) { events.values.append(event) }
            }
            defer { stream.cancel() }
            _ = try await self.send(
                "Fetch.enable", ["patterns": [["resourceType": "Document", "requestStage": "Response"]]], store: store,
                target: target, client: client)
            _ = try await page.evaluateJavaScript(
                """
                globalThis.fetchResult = 'pending';
                const url = URL.createObjectURL(new Blob(['not-a-document'], {type: 'text/plain'}));
                fetch(url).then(response => response.text()).then(text => { fetchResult = text; });
                undefined
                """)
            try await BrowserChromeDebuggerDomainFixture.waitFor {
                (try await page.evaluateJavaScript("fetchResult")) as? String == "not-a-document"
            }
            XCTAssertTrue(events.parameters("Fetch.requestPaused").isEmpty)
            // Repeated enable changes the match set on the same attachment.
            _ = try await self.send("Fetch.enable", ["patterns": []], store: store, target: target, client: client)
            _ = try await self.send(
                "Fetch.enable", ["patterns": [["requestStage": "Response"]]], store: store, target: target,
                client: client)
            _ = try await self.send("Fetch.disable", [:], store: store, target: target, client: client)
        }
    }

    func testRuntimeEnableAlsoDeliversConsoleOutputToTheClient() async throws {
        try await withSession { store, page, target, client in
            let events = EventRecorder()
            let stream = Task { @MainActor in
                for await event in store.events(for: client) { events.values.append(event) }
            }
            defer { stream.cancel() }
            _ = try await self.send("Runtime.enable", [:], store: store, target: target, client: client)
            _ = try await page.evaluateJavaScript("console.log('crest-through-the-store'); undefined")
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
                events.method("Runtime.consoleAPICalled") { parameters in
                    (parameters["args"] as? [[String: Any]])?.first?["value"] as? String
                        == "crest-through-the-store"
                }
            }
        }
    }

    func testPageAndNetworkEventsBothReachTheClientFromOneConnection() async throws {
        try await withSession { store, page, target, client in
            let events = EventRecorder()
            let stream = Task { @MainActor in
                for await event in store.events(for: client) { events.values.append(event) }
            }
            defer { stream.cancel() }
            _ = try await self.send("Page.enable", [:], store: store, target: target, client: client)
            _ = try await self.send("Network.enable", [:], store: store, target: target, client: client)
            let second = try self.writeDocument(named: "second.html")
            defer { try? FileManager.default.removeItem(at: second.deletingLastPathComponent()) }
            page.loadFileURL(second, allowingReadAccessTo: second.deletingLastPathComponent())
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
                events.method("Page.frameNavigated") { parameters in
                    ((parameters["frame"] as? [String: Any])?["url"] as? String)?.hasSuffix("second.html") == true
                }
            }
            // A network document the engine reports on the same connection: the
            // host never resolves, but the request is announced before that.
            page.load(URLRequest(url: try XCTUnwrap(URL(string: "https://crest.invalid/routing"))))
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
                events.method("Network.requestWillBeSent") { $0["type"] as? String == "Document" }
            }
        }
    }

    func testTabCommandsAreUnsupportedWithoutATabHostAndSupportedWithOne() async throws {
        try await withSession { store, _, target, client in
            do {
                _ = try await self.send("Page.bringToFront", [:], store: store, target: target, client: client)
                XCTFail("Without a tab host there is no tab to bring forward.")
            } catch BrowserExtensionDebuggerError.unsupportedCommand("Page.bringToFront") {}
            do {
                _ = try await self.send("Overlay.enable", [:], store: store, target: target, client: client)
                XCTFail("An unrouted domain must report unsupported.")
            } catch BrowserExtensionDebuggerError.unsupportedCommand("Overlay.enable") {}
        }
    }

    func testInputAndTargetCommandsRouteThroughTheStore() async throws {
        try await withSession { store, page, target, client in
            let response = try await self.send("Target.getTargets", [:], store: store, target: target, client: client)
            let infos = try XCTUnwrap(response["targetInfos"] as? [[String: Any]])
            XCTAssertEqual(infos.first?["targetId"] as? String, target.tabID.rawValue.uuidString)
            _ = try await self.send(
                "Input.insertText", ["text": "routed"], store: store, target: target, client: client)
        }
    }

    func testAccessibilityNodeCanBeResolvedThroughTheSameSession() async throws {
        try await withSession { store, page, target, client in
            _ = try await page.evaluateJavaScript(
                "document.body.innerHTML = '<button>Routed control</button>'; undefined")
            _ = try await self.send("Accessibility.enable", [:], store: store, target: target, client: client)
            let tree = try await self.send(
                "Accessibility.getFullAXTree", [:], store: store, target: target, client: client)
            let nodes = try XCTUnwrap(tree["nodes"] as? [[String: Any]])
            let button = try XCTUnwrap(
                nodes.first { ($0["name"] as? [String: Any])?["value"] as? String == "Routed control" })
            let resolved = try await self.send(
                "DOM.resolveNode", ["backendNodeId": try XCTUnwrap(button["backendDOMNodeId"])], store: store,
                target: target, client: client)
            let objectID = try XCTUnwrap((resolved["object"] as? [String: Any])?["objectId"] as? String)
            let result = try await self.send(
                "Runtime.callFunctionOn",
                [
                    "objectId": objectID,
                    "functionDeclaration": "function() { return this.localName; }", "returnByValue": true,
                ],
                store: store, target: target, client: client)
            XCTAssertEqual((result["result"] as? [String: Any])?["value"] as? String, "button")
        }
    }

    func testSnapshotRoutesThroughSessionAndRejectsUnavailableRenderOptions() async throws {
        try await withSession { store, page, target, client in
            _ = try await page.evaluateJavaScript(
                "document.body.innerHTML = '<h1>Routed snapshot</h1>'; undefined")
            let result = try await self.send(
                "DOMSnapshot.captureSnapshot",
                ["computedStyles": [], "includePaintOrder": false, "includeDOMRects": false],
                store: store, target: target, client: client)
            XCTAssertTrue((result["strings"] as? [String] ?? []).contains("Routed snapshot"))
            let documents = try XCTUnwrap(result["documents"] as? [[String: Any]])
            XCTAssertEqual(documents.count, 1)
            let layout = try XCTUnwrap(documents[0]["layout"] as? [String: Any])
            XCTAssertFalse((layout["bounds"] as? [[Double]] ?? []).isEmpty)
            for option in [
                "includePaintOrder", "includeDOMRects", "includeBlendedBackgroundColors", "includeTextColorOpacities",
            ] {
                do {
                    _ = try await self.send(
                        "DOMSnapshot.captureSnapshot", ["computedStyles": [], option: true],
                        store: store, target: target, client: client)
                    XCTFail("Unavailable rendering details must reject explicitly.")
                } catch BrowserChromeDebuggerProtocolError.unsupportedParameter(option) {}
            }
        }
    }

    private func writeDocument(named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crest-routing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("<!doctype html><title>Crest routed document</title>".utf8).write(to: url)
        return url
    }

    private func send(
        _ method: String, _ parameters: [String: Any], store: BrowserExtensionDebuggerSessionStore,
        target: BrowserExtensionDebuggerTarget, client: BrowserExtensionServiceClientID
    ) async throws -> [String: Any] {
        let bytes = try await store.sendCommand(
            .init(method: method, parameters: try JSONSerialization.data(withJSONObject: parameters)),
            to: target, for: client)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private func withSession(
        _ operation: (
            BrowserExtensionDebuggerSessionStore, WKWebView, BrowserExtensionDebuggerTarget,
            BrowserExtensionServiceClientID
        ) async throws -> Void
    ) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences)
        let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        page.isInspectable = true
        // Started from a file the page can navigate away from and back to: an
        // HTML string has no document WebKit can fetch again.
        let start = try writeDocument(named: "start.html")
        defer {
            page.stopLoading()
            try? FileManager.default.removeItem(at: start.deletingLastPathComponent())
        }
        page.loadFileURL(start, allowingReadAccessTo: start.deletingLastPathComponent())
        try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
            (try? await page.evaluateJavaScript("document.readyState")) as? String == "complete"
        }
        let space = SpaceID()
        let target = BrowserExtensionDebuggerTarget(spaceID: space, tabID: TabID())
        let client = BrowserExtensionServiceClientID.scoped(extensionID: "routing", spaceID: space)
        let store = BrowserExtensionDebuggerSessionStore(
            authorizeClient: { _ in true },
            resolveTarget: { requested in requested == target ? .available(page) : .closed })
        store.register(client: client, spaceID: space, displayName: "Routing extension")
        defer { store.shutdown() }
        try await store.attach(to: target, for: client, requiredVersion: "1.3")
        try await operation(store, page, target, client)
    }

    @MainActor
    private final class EventRecorder {
        var values: [BrowserExtensionDebuggerEvent] = []

        func parameters(_ name: String) -> [[String: Any]] {
            values.compactMap { event in
                guard case .protocolMessage(let method, let bytes) = event.kind, method == name else { return nil }
                return try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            }
        }

        func method(_ name: String, where predicate: ([String: Any]) -> Bool) -> Bool {
            values.contains { event in
                guard case .protocolMessage(let method, let parameters) = event.kind, method == name,
                    let decoded = try? JSONSerialization.jsonObject(with: parameters) as? [String: Any]
                else { return false }
                return predicate(decoded)
            }
        }
    }
}
