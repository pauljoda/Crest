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
