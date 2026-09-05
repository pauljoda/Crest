import Network
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionHostedContentIsolationTests: XCTestCase {
    func testHostedManifestCSPStillBlocksInlineScriptAndEvalWhileWebsiteScriptsRun() async throws {
        let server = try FrameServer()
        defer { server.stop() }
        let frameURL = try await server.start()
        let root = try fixture(
            name: "Panel CSP owner",
            manifest: [
                "manifest_version": 3,
                "content_security_policy": ["extension_pages": "script-src 'self'; object-src 'self'"],
            ],
            files: [
                "panel.html": """
                <html><body><script>globalThis.inlineScriptRan = true;</script>
                <script src="panel.js"></script><iframe src="\(frameURL)"></iframe></body></html>
                """,
                "panel.js": """
                globalThis.packagedScriptRan = true;
                try { eval('globalThis.evalRan = true'); } catch { globalThis.evalBlocked = true; }
                addEventListener('message', event => {
                    if (event.source === frames[0]) globalThis.websiteReplied = true;
                });
                setInterval(() => frames[0]?.postMessage('probe', '*'), 25);
                """,
            ])
        defer { try? FileManager.default.removeItem(at: root) }
        let controllerConfiguration = WKWebExtensionController.Configuration.nonPersistent()
        controllerConfiguration.defaultWebsiteDataStore = .nonPersistent()
        let controller = WKWebExtensionController(configuration: controllerConfiguration)
        let owner = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: root))
        owner.hasAccessToPrivateData = true
        try controller.load(owner)
        defer { try? controller.unload(owner) }
        let configuration = try XCTUnwrap(owner.webViewConfiguration)
        XCTAssertTrue(BrowserExtensionHostedWebsiteDataStore.apply(.nonPersistent(), to: configuration))
        XCTAssertTrue(
            BrowserExtensionHostedPageConfigurationPolicy.clearExtensionContentSecurityPolicyMode(on: configuration))
        let document = BrowserExtensionSidebarDocument(
            url: owner.baseURL.appending(path: "panel.html"), tabID: nil,
            configuration: .init(
                baseURL: owner.baseURL, context: owner, webViewConfiguration: configuration,
                clientID: .scoped(extensionID: "owner", spaceID: SpaceID())),
            cookieAccess: nil, openTab: { _ in XCTFail("The fixture must stay inside its panel") })
        defer { document.close() }
        let panel = try XCTUnwrap(document.webView)
        try await waitUntilLoaded(panel)
        let result =
            try await panel.callAsyncJavaScript(
                """
                for (let i = 0; i < 100 && !globalThis.websiteReplied; ++i)
                    await new Promise(resolve => setTimeout(resolve, 25));
                return [!!globalThis.packagedScriptRan, !!globalThis.inlineScriptRan,
                        !!globalThis.evalRan, !!globalThis.evalBlocked, !!globalThis.websiteReplied];
                """, arguments: [:], in: nil, contentWorld: .page) as? [Bool]
        XCTAssertEqual(result, [true, false, false, true, true])
    }

    func testNativeForeignExtensionIsExcludedWhileTheOwnerCanReachItsBackground() async throws {
        let server = try FrameServer()
        defer { server.stop() }
        let frameURL = try await server.start()
        let ownerRoot = try fixture(
            name: "Panel owner",
            manifest: [
                "permissions": ["storage"],
                "background": ["scripts": ["background.js"]],
            ],
            files: [
                "panel.html": "<html><body><iframe src='\(frameURL)'></iframe></body></html>",
                "background.js":
                    "browser.runtime.onMessage.addListener((message, sender, reply) => { browser.storage.local.get('hostedMarker').then(value => reply({owner: 'awake', marker: value.hostedMarker})); return true; });",
            ])
        defer { try? FileManager.default.removeItem(at: ownerRoot) }
        let foreignRoot = try fixture(
            name: "Foreign theme",
            manifest: [
                "permissions": ["<all_urls>"],
                "content_scripts": [
                    ["matches": ["<all_urls>"], "js": ["foreign.js"], "css": ["foreign.css"], "all_frames": true]
                ],
            ],
            files: [
                "foreign.js": "document.documentElement.dataset.foreignExtension = 'present';",
                "foreign.css": "body { --foreign-theme: present; }",
            ])
        defer { try? FileManager.default.removeItem(at: foreignRoot) }
        let controllerConfiguration = WKWebExtensionController.Configuration.nonPersistent()
        controllerConfiguration.defaultWebsiteDataStore = .nonPersistent()
        let controller = WKWebExtensionController(configuration: controllerConfiguration)
        let owner = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: ownerRoot))
        owner.hasAccessToPrivateData = true
        owner.setPermissionStatus(.grantedExplicitly, for: .storage)
        try controller.load(owner)
        defer { try? controller.unload(owner) }
        let configuration = try XCTUnwrap(owner.webViewConfiguration)
        XCTAssertTrue(BrowserExtensionHostedWebsiteDataStore.apply(.nonPersistent(), to: configuration))
        BrowserExtensionHostedPageConfigurationPolicy.clearExtensionContentSecurityPolicyMode(on: configuration)
        let document = BrowserExtensionSidebarDocument(
            url: owner.baseURL.appending(path: "panel.html"), tabID: nil,
            configuration: .init(
                baseURL: owner.baseURL, context: owner, webViewConfiguration: configuration,
                clientID: .scoped(extensionID: "owner", spaceID: SpaceID())),
            cookieAccess: nil, openTab: { _ in XCTFail("The fixture must stay inside its panel") })
        defer { document.close() }
        let panel = try XCTUnwrap(document.webView)
        try await waitUntilLoaded(panel)

        _ = try await panel.callAsyncJavaScript(
            "await browser.storage.local.set({hostedMarker: 'shared-native-storage'}); return true;",
            arguments: [:], in: nil, contentWorld: .page)
        let ownerReply =
            try await panel.callAsyncJavaScript(
                "return await browser.runtime.sendMessage({ping: true});", arguments: [:], in: nil, contentWorld: .page)
            as? [String: String]
        XCTAssertEqual(ownerReply, ["owner": "awake", "marker": "shared-native-storage"])

        // Load a real second extension after the panel already exists. WebKit
        // injects its content immediately into registered controllers.
        let foreign = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: foreignRoot))
        foreign.hasAccessToPrivateData = true
        foreign.setPermissionStatus(.grantedExplicitly, for: try WKWebExtension.MatchPattern(string: "<all_urls>"))
        try controller.load(foreign)
        defer { try? controller.unload(foreign) }
        let normalConfiguration = WKWebViewConfiguration()
        normalConfiguration.websiteDataStore = controllerConfiguration.defaultWebsiteDataStore
        normalConfiguration.webExtensionController = controller
        let tab = WKWebView(frame: .zero, configuration: normalConfiguration)
        tab.load(URLRequest(url: URL(string: frameURL)!))
        try await waitUntilLoaded(tab)
        let probe =
            "[document.documentElement.dataset.foreignExtension === 'present', getComputedStyle(document.body).getPropertyValue('--foreign-theme').trim() === 'present']"
        let tabResult = try await tab.evaluateJavaScript(probe) as? [Bool]
        XCTAssertEqual(
            tabResult, [true, true], "The real foreign extension must still style and script an ordinary tab.")
        let frameProbe = """
            return await new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error('No frame reply')), 3000);
                addEventListener('message', function listener(event) {
                    if (event.source !== frames[0]) return;
                    removeEventListener('message', listener); clearTimeout(timeout); resolve(event.data);
                });
                frames[0].postMessage('probe', '*');
            });
            """
        let embeddedResult =
            try await panel.callAsyncJavaScript(frameProbe, arguments: [:], in: nil, contentWorld: .page) as? [Bool]
        XCTAssertEqual(
            embeddedResult, [false, false], "The embedded website must not receive another extension's scripts or CSS.")
        panel.reload()
        try await waitUntilLoaded(panel)
        let reloadedResult =
            try await panel.callAsyncJavaScript(frameProbe, arguments: [:], in: nil, contentWorld: .page) as? [Bool]
        XCTAssertEqual(reloadedResult, [false, false])
    }

    func testSharedScriptsCannotReachHostedDocumentsOrFramesButStillReachTabs() async throws {
        let shared = WKUserContentController()
        shared.addUserScript(
            WKUserScript(
                source: "globalThis.foreignExtensionRan = true;",
                injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = shared
        let isolated = WKUserContentController()
        isolated.addUserScript(
            WKUserScript(
                source: "globalThis.hostBridgeRan = true;",
                injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let panel = WKWebView(frame: .zero, configuration: configuration)
        let normalConfiguration = WKWebViewConfiguration()
        normalConfiguration.websiteDataStore = .nonPersistent()
        normalConfiguration.userContentController = shared
        let tab = WKWebView(frame: .zero, configuration: normalConfiguration)
        let html = "<html><body><iframe srcdoc='<p>Embedded website</p>'></iframe></body></html>"
        try await load(html, in: panel, isolatedController: isolated)
        try await load(html, in: tab)
        let probe =
            "[!!globalThis.foreignExtensionRan, !!frames[0].foreignExtensionRan, !!globalThis.hostBridgeRan, !!frames[0].hostBridgeRan]"
        let panelResult = try await panel.evaluateJavaScript(probe) as? [Bool]
        let tabResult = try await tab.evaluateJavaScript(probe) as? [Bool]
        XCTAssertEqual(panelResult, [false, false, true, true])
        XCTAssertEqual(tabResult, [true, true, false, false])

        // Enabling another extension after opening the panel must not enroll
        // this controller, including after a subsequent frame navigation.
        shared.addUserScript(
            WKUserScript(
                source: "globalThis.laterExtensionRan = true;",
                injectionTime: .atDocumentStart, forMainFrameOnly: false))
        try await load(html, in: panel, isolatedController: isolated)
        try await load(html, in: tab)
        let laterProbe = "[!!globalThis.laterExtensionRan, !!frames[0].laterExtensionRan]"
        let isolatedLater = try await panel.evaluateJavaScript(laterProbe) as? [Bool]
        let normalLater = try await tab.evaluateJavaScript(laterProbe) as? [Bool]
        XCTAssertEqual(isolatedLater, [false, false])
        XCTAssertEqual(normalLater, [true, true])
    }

    private func load(_ html: String, in webView: WKWebView, isolatedController: WKUserContentController? = nil)
        async throws
    {
        let waiter = NavigationWaiter(
            controller: isolatedController, originalPreferences: webView.configuration.defaultWebpagePreferences)
        webView.navigationDelegate = waiter
        webView.loadSimulatedRequest(
            URLRequest(url: URL(string: "https://panel-isolation.crest.test/")!), responseHTML: html)
        await fulfillment(of: [waiter.finished], timeout: 10)
        if let error = waiter.error { throw error }
    }

    private func waitUntilLoaded(_ webView: WKWebView) async throws {
        for _ in 0..<400 {
            if !webView.isLoading,
                (try? await webView.evaluateJavaScript("document.readyState")) as? String == "complete"
            {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("The fixture did not finish loading")
    }

    private func fixture(name: String, manifest: [String: Any], files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-isolation-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var result: [String: Any] = ["manifest_version": 2, "name": name, "version": "1.0"]
        result.merge(manifest) { _, new in new }
        try JSONSerialization.data(withJSONObject: result).write(to: root.appending(path: "manifest.json"))
        for (name, content) in files {
            try content.write(to: root.appending(path: name), atomically: true, encoding: .utf8)
        }
        return root
    }

    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        let finished = XCTestExpectation(description: "Hosted document and its frames loaded")
        var error: Error?
        let controller: WKUserContentController?
        let originalPreferences: WKWebpagePreferences?

        init(controller: WKUserContentController?, originalPreferences: WKWebpagePreferences?) {
            self.controller = controller
            self.originalPreferences = originalPreferences
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            if let controller {
                XCTAssertFalse(preferences === originalPreferences, "Only WebKit's navigation copy may be changed.")
                XCTAssertTrue(BrowserExtensionHostedContentIsolationPolicy.apply(controller, to: preferences))
            }
            decisionHandler(.allow, preferences)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) { finished.fulfill() }
        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error
        ) {
            self.error = error
            finished.fulfill()
        }
    }
}

/// A local website is necessary to exercise cross-origin extension frames;
/// srcdoc alone inherits the extension origin and cannot catch this leak.
private final class FrameServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "CrestTests.HostedIsolation.HTTP")
    init() throws { listener = try NWListener(using: .tcp, on: .any) }
    func start() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: "http://127.0.0.1:\(listener.port!.rawValue)/")
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [queue] connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                    let body = """
                        <html><body>Isolated website<script>
                        addEventListener('message', event => {
                            if (event.data !== 'probe') return;
                            event.source.postMessage([
                                document.documentElement.dataset.foreignExtension === 'present',
                                getComputedStyle(document.body).getPropertyValue('--foreign-theme').trim() === 'present'
                            ], '*');
                        });
                        </script></body></html>
                        """
                    let response =
                        "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(
                        content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.start(queue: queue)
        }
    }
    func stop() { listener.cancel() }
}
