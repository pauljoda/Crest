import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionBackgroundHealthTests: XCTestCase {
    func testBackgroundRecoveryPreservesContentScriptsAndStoredState() async throws {
        defer { WKWebsiteDataStore.remove(forIdentifier: BrowserSession.preview.spaces[0].profile.id) { _ in } }
        for usesWorker in [true, false] {
            try await verifyBackgroundRecovery(usesWorker: usesWorker)
        }
    }

    private func verifyBackgroundRecovery(usesWorker: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-background-recovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let background: [String: Any] = usesWorker
            ? ["service_worker": "background.js"]
            : ["scripts": ["background.js"], "persistent": false]
        let manifest: [String: Any] = [
            "manifest_version": 3, "name": "Background Recovery", "version": "1.0",
            "permissions": ["storage"], "background": background, "action": [:],
            "host_permissions": ["http://127.0.0.1/*"],
            "content_scripts": [["matches": ["http://127.0.0.1/*"], "js": ["content.js"]]],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appending(path: "manifest.json"))
        try Data("""
            chrome.runtime.onMessage.addListener((message, sender, reply) => {
                Promise.all([chrome.storage.local.get('marker'), chrome.storage.session.get('marker')])
                    .then(([local, session]) => reply({nonce: message.probe, local: local.marker, session: session.marker}));
                return true;
            });
            chrome.action.onClicked.addListener(() => {});
            """.utf8).write(to: root.appending(path: "background.js"))
        try Data("<!doctype html><body>Probe</body>".utf8).write(to: root.appending(path: "probe.html"))
        try Data("""
            document.documentElement.dataset.injections = Number(document.documentElement.dataset.injections || 0) + 1;
            """.utf8).write(to: root.appending(path: "content.js"))
        let server = try BrowserPrivacyHTTPServer()
        server.overrideResponse = { _ in
            ("200 OK", "Content-Type: text/html\r\n", Data("<html><body>Probe</body></html>".utf8))
        }
        try await server.start()
        defer { server.stop() }
        let pool = BrowserExtensionControllerPool(
            storedResourcePreparer: BrowserStoreWebExtensionStoredResourcePreparer(), usesEphemeralWebKitStorage: false)
        pool.setNativeMessagingHandler(BrowserNativeMessagingService(
            capability: .available, resolver: BrowserNativeMessagingHostManifestResolver(searchDirectories: [])))
        let space = BrowserSession.preview.spaces[0]
        let summary = try await pool.loadUnpackedExtension(from: root, in: space)
        let context = try XCTUnwrap(pool.loadedContext(extensionID: summary.id, in: space.id))
        context.setPermissionStatus(.grantedExplicitly, for: .storage)
        let controller = pool.controller(for: space)
        defer { try? controller.unload(context) }
        let initial = await pool.tabWindowCoordinator.prepareBackgroundForInitialContentScriptTraffic(context)
        guard case .loaded = initial else { return XCTFail("Initial background did not become ready") }
        let client = BrowserExtensionServiceClientID.scoped(extensionID: summary.id, spaceID: space.id)
        let health = BrowserExtensionBackgroundHealth.shared
        let page = WKWebView(frame: .zero, configuration: try XCTUnwrap(context.webViewConfiguration))
        page.load(URLRequest(url: context.baseURL.appending(path: "probe.html")))
        for _ in 0..<100 {
            if !page.isLoading,
                (try? await page.evaluateJavaScript("document.body?.textContent")) as? String == "Probe" { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        _ = try await page.callAsyncJavaScript(
            "await chrome.storage.local.set({marker: 'preserved'}); await chrome.storage.session.set({marker: 'session preserved'}); return true;",
            arguments: [:], contentWorld: .page)
        context.hasAccessToPrivateData = true
        context.setPermissionStatus(.grantedExplicitly, for: try WKWebExtension.MatchPattern(string: "<all_urls>"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = controller.configuration.defaultWebsiteDataStore
        configuration.webExtensionController = controller
        let website = WKWebView(frame: .zero, configuration: configuration)
        website.load(URLRequest(url: server.url(host: "127.0.0.1", path: "/")))
        let injectionCount = "document.documentElement.dataset.injections"
        for _ in 0..<100 {
            if (try? await website.evaluateJavaScript(injectionCount)) as? String == "1" { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let initialCount = try await website.evaluateJavaScript(injectionCount) as? String
        XCTAssertEqual(initialCount, "1")

        for attempt in 1...2 {
            // A stale broker endpoint reproduces the failed health challenge
            // without depending on WebKit's idle timer or killing a process.
            health.register(client: client, id: UUID()) { _ in }
            pool.tabWindowCoordinator.requestToolbarAction(for: context, tab: nil)
            for _ in 0..<200 where pool.tabWindowCoordinator.isActionPopupLoading(for: context) {
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertFalse(pool.tabWindowCoordinator.isActionPopupLoading(for: context))
            let recovered = await health.responds(client: client)
            XCTAssertTrue(recovered, "Background did not recover, worker=\(usesWorker), attempt=\(attempt)")
            let reply = try await page.callAsyncJavaScript(
                "return await chrome.runtime.sendMessage({probe: 'recovered'});", arguments: [:], contentWorld: .page)
                as? [String: Any]
            XCTAssertEqual(reply?["nonce"] as? String, "recovered")
            XCTAssertEqual(reply?["local"] as? String, "preserved")
            XCTAssertEqual(reply?["session"] as? String, "session preserved")
            let recoveredCount = try await website.evaluateJavaScript(injectionCount) as? String
            XCTAssertEqual(recoveredCount, "1", "Recovery must not duplicate existing content scripts")
        }
    }

    func testBackgroundHealthWatchRequiresInternalBrokerAuthorization() throws {
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("health-test"))
        let connection = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(clientID: client), notificationService: nil,
            idleStateProvider: { _ in .active }, webpageMenuRegistry: .init(), publish: { _ in }
        )
        XCTAssertThrowsError(try connection.receive(["api": "background.health.watch"]))
        XCTAssertThrowsError(try connection.receive(["api": "background.health.pong", "nonce": "unknown"]))
    }

    func testBackgroundHealthRequiresAResponseFromTheChallengedEndpoint() async throws {
        let health = BrowserExtensionBackgroundHealth()
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("health-test"))
        let endpoint = UUID()
        health.register(client: client, id: endpoint) { message in
            health.acknowledge(nonce: message["nonce"] as! String, endpoint: UUID())
        }
        let wrongEndpoint = await health.responds(client: client, timeout: .milliseconds(20))
        XCTAssertFalse(wrongEndpoint)
        health.register(client: client, id: endpoint) { message in
            health.acknowledge(nonce: message["nonce"] as! String, endpoint: endpoint)
        }
        let answered = await health.responds(client: client)
        XCTAssertTrue(answered)
    }

    func testBackgroundHealthRejectsDisconnectedEndpointWithoutWaiting() async throws {
        let health = BrowserExtensionBackgroundHealth()
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("health-test"))
        let endpoint = UUID()
        health.register(client: client, id: endpoint) { _ in
            health.unregister(client: client, id: endpoint)
        }
        let answered = await health.responds(client: client)
        XCTAssertFalse(answered)
    }

    func testOldDisconnectDoesNotRemoveReplacementBackground() async throws {
        let health = BrowserExtensionBackgroundHealth()
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("health-test"))
        let old = UUID()
        let replacement = UUID()
        var challengedNonce: String?
        health.register(client: client, id: old) { challengedNonce = $0["nonce"] as? String }
        let oldReply = Task { await health.responds(client: client) }
        while challengedNonce == nil { await Task.yield() }
        health.register(client: client, id: replacement) { message in
            health.acknowledge(nonce: message["nonce"] as! String, endpoint: replacement)
        }
        health.acknowledge(nonce: try XCTUnwrap(challengedNonce), endpoint: old)
        let oldAnswered = await oldReply.value
        XCTAssertFalse(oldAnswered, "A replaced endpoint must not satisfy the outstanding challenge.")
        health.unregister(client: client, id: old)
        XCTAssertEqual(health.endpointID(for: client), replacement)
        let answered = await health.responds(client: client)
        XCTAssertTrue(answered)
    }
}
