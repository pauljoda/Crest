import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionHostedContentIsolationTests: XCTestCase {
    func testRestoringMenusForEmbeddedExtensionDoesNotTerminateWebpage() async throws {
        let browser = BrowserStore.preview()
        let space = try XCTUnwrap(browser.selectedSpace)
        let registry = BrowserExtensionWebpageMenuRegistry()
        let pool = BrowserExtensionControllerPool(
            storedResourcePreparer: BrowserStoreWebExtensionStoredResourcePreparer(),
            webpageMenuRegistry: registry)
        pool.setNativeMessagingHandler(
            BrowserNativeMessagingService(
                capability: .available,
                resolver: BrowserNativeMessagingHostManifestResolver(searchDirectories: []),
                webpageMenuRegistry: registry))
        let root = try fixture(
            name: "Embedded extension menu restoration",
            manifest: [
                "permissions": ["contextMenus"],
                "background": ["scripts": ["background.js"]],
                "web_accessible_resources": ["frame.html"],
            ],
            files: [
                "frame.html": "<html><body>Extension frame</body></html>",
                "background.js": "browser.runtime.onMessage.addListener(() => Promise.resolve('awake'));",
            ])
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = try await pool.loadUnpackedExtension(from: root, in: space)
        let context = try XCTUnwrap(pool.loadedContext(extensionID: installed.id, in: space.id))
        try await pool.setPermissionDecision(.allow, for: "contextMenus", extensionID: installed.id, in: space)
        let client = BrowserExtensionServiceClientID.scoped(extensionID: installed.id, spaceID: space.id)
        try registry.replaceDefinitions(
            message: [
                "api": "contextMenus.replace",
                "items": [
                    [
                        "id": "string:probe", "type": "normal", "title": "Probe", "contexts": ["page"],
                        "documentUrlPatterns": [], "targetUrlPatterns": [], "enabled": true, "visible": true,
                    ] as [String: Any]
                ],
            ], for: client)
        let server = try frameServer()
        defer { server.stop() }
        try await server.start()
        let controller = pool.controller(for: space)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = controller.configuration.defaultWebsiteDataStore
        configuration.webExtensionController = controller
        let tab = WKWebView(frame: .zero, configuration: configuration)
        let observer = NavigationWaiter(controller: nil, originalPreferences: nil)
        tab.navigationDelegate = observer
        tab.load(URLRequest(url: server.url(host: "127.0.0.1", path: "/")))
        try await waitUntilLoaded(tab)
        let marker = UUID().uuidString
        let result = try? await tab.callAsyncJavaScript(
            """
            globalThis.unsavedMarker = marker;
            const frame = document.createElement('iframe');
            frame.src = frameURL;
            document.body.appendChild(frame);
            await new Promise(resolve => setTimeout(resolve, 1500));
            return globalThis.unsavedMarker;
            """,
            arguments: ["marker": marker, "frameURL": context.baseURL.appending(path: "frame.html").absoluteString],
            contentWorld: .page)
        XCTAssertEqual(observer.terminations, 0, "Restoring an extension frame must not kill its containing webpage")
        XCTAssertEqual(result as? String, marker, "The containing webpage must retain its live state")
        XCTAssertEqual(registry.definitions(for: client).map(\.title), ["Probe"])

        // A top-level extension document still owns privileged menu APIs and
        // must restore persisted menus even when no background recreates them.
        let topLevel = WKWebView(frame: .zero, configuration: try XCTUnwrap(context.webViewConfiguration))
        topLevel.load(URLRequest(url: context.baseURL.appending(path: "frame.html")))
        try await waitUntilLoaded(topLevel)
        let restored = try await topLevel.callAsyncJavaScript(
            """
            for (let attempt = 0; attempt < 40; ++attempt) {
                try {
                    await browser.contextMenus.update('probe', {title: 'Restored Probe'});
                    return true;
                } catch { await new Promise(resolve => setTimeout(resolve, 25)); }
            }
            return false;
            """, arguments: [:], contentWorld: .page)
        XCTAssertEqual(restored as? Bool, true, "Top-level extension menu restoration must remain functional")
    }

    func testBackgroundCanRestartWhileAnIsolatedPanelRemainsOpen() async throws {
        let root = try fixture(
            name: "Panel background recovery",
            manifest: [
                "permissions": ["storage"],
                "background": ["scripts": ["background.js"], "persistent": false],
            ],
            files: [
                "panel.html": "<!doctype html><title>Background recovery</title>",
                "background.js": """
                browser.runtime.onMessage.addListener(async () => {
                    const value = await browser.storage.local.get('marker');
                    return value.marker;
                });
                """,
            ])
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = WKWebExtensionController.Configuration.nonPersistent()
        configuration.defaultWebsiteDataStore = .nonPersistent()
        let controller = WKWebExtensionController(configuration: configuration)
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: root))
        context.hasAccessToPrivateData = true
        context.setPermissionStatus(.grantedExplicitly, for: .storage)
        try controller.load(context)
        defer { try? controller.unload(context) }
        let document = BrowserExtensionSidebarDocument(
            url: context.baseURL.appending(path: "panel.html"), tabID: nil,
            configuration: .init(
                baseURL: context.baseURL, context: context,
                webViewConfiguration: try XCTUnwrap(context.webViewConfiguration),
                clientID: .scoped(extensionID: "recovery", spaceID: SpaceID())),
            openTab: { _ in XCTFail("Recovery must keep the existing panel") })
        defer { document.close() }
        let panel = try XCTUnwrap(document.webView)
        try await waitUntilLoaded(panel)
        _ = try await panel.callAsyncJavaScript(
            "await browser.storage.local.set({marker:'survives-background-restart'});",
            arguments: [:], contentWorld: .page)
        let initial = try await panel.callAsyncJavaScript(
            "return await browser.runtime.sendMessage({ping:true});", arguments: [:], contentWorld: .page)
        XCTAssertEqual(initial as? String, "survives-background-restart")
        let previousBackground = try XCTUnwrap(context.value(forKey: "_backgroundWebView") as? WKWebView)
        XCTAssertFalse(previousBackground.configuration.websiteDataStore === panel.configuration.websiteDataStore)

        // WebKit must not choose the isolated panel as the new background's
        // related view: that relationship requires the very same data store.
        for _ in 0..<450 {
            if context.value(forKey: "_backgroundWebView") == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(context.value(forKey: "_backgroundWebView"), "The background must actually idle out")
        let recovered = try await panel.callAsyncJavaScript(
            "return await browser.runtime.sendMessage({ping:true});", arguments: [:], contentWorld: .page)
        let replacement = try XCTUnwrap(context.value(forKey: "_backgroundWebView") as? WKWebView)
        XCTAssertFalse(previousBackground === replacement)
        XCTAssertEqual(recovered as? String, "survives-background-restart")
        XCTAssertTrue(document.webView === panel)
    }

    func testHostedManifestCSPStillBlocksInlineScriptAndEvalWhileWebsiteScriptsRun() async throws {
        let server = try frameServer()
        defer { server.stop() }
        try await server.start()
        let frameURL = server.url(host: "127.0.0.1", path: "/").absoluteString
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
        XCTAssertTrue(
            BrowserExtensionHostedPageConfigurationPolicy.clearExtensionContentSecurityPolicyMode(on: configuration))
        let document = BrowserExtensionSidebarDocument(
            url: owner.baseURL.appending(path: "panel.html"), tabID: nil,
            configuration: .init(
                baseURL: owner.baseURL, context: owner, webViewConfiguration: configuration,
                clientID: .scoped(extensionID: "owner", spaceID: SpaceID())),
            openTab: { _ in XCTFail("The fixture must stay inside its panel") })
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
        let server = try frameServer()
        defer { server.stop() }
        try await server.start()
        let frameURL = server.url(host: "127.0.0.1", path: "/").absoluteString
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
        BrowserExtensionHostedPageConfigurationPolicy.clearExtensionContentSecurityPolicyMode(on: configuration)
        let document = BrowserExtensionSidebarDocument(
            url: owner.baseURL.appending(path: "panel.html"), tabID: nil,
            configuration: .init(
                baseURL: owner.baseURL, context: owner, webViewConfiguration: configuration,
                clientID: .scoped(extensionID: "owner", spaceID: SpaceID())),
            openTab: { _ in XCTFail("The fixture must stay inside its panel") })
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
            if webView.url != nil, !webView.isLoading,
                (try? await webView.evaluateJavaScript("document.readyState")) as? String == "complete"
            {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(
            domain: "CrestHostedContentFixture", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "The fixture did not finish loading"
            ])
    }

    /// A real cross-origin website catches leaks that extension-origin srcdoc cannot.
    private func frameServer() throws -> BrowserPrivacyHTTPServer {
        let server = try BrowserPrivacyHTTPServer()
        server.overrideResponse = { _ in
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
            return ("200 OK", "Content-Type: text/html\r\n", Data(body.utf8))
        }
        return server
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
        var terminations = 0
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

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { terminations += 1 }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) { finished.fulfill() }
        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error
        ) {
            self.error = error
            finished.fulfill()
        }
    }
}
