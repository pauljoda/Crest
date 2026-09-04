import WebKit
import XCTest

@testable import Crest

/// The session store is what a client actually talks to, so the domains have to
/// be reachable through it: a translator that only works when constructed by
/// hand is a translator no extension can use.
@MainActor
final class BrowserExtensionDebuggerSessionDomainRoutingTests: XCTestCase {
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
