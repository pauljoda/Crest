import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionWebsiteDataTests: XCTestCase {
    func testPanelSessionAuthenticatesOnlyPermittedFramesWithoutChangingBrowserCookies() async throws {
        try await exercisePanelSession(persistent: false)
    }

    func testPersistentProfileWithBroadHostPermissionClearsItsPanelSessionOnLogout() async throws {
        try await exercisePanelSession(persistent: true)
    }

    private func exercisePanelSession(persistent: Bool) async throws {
        let server = try BrowserPrivacyHTTPServer(tls: true)
        try await server.start()
        defer { server.stop() }
        server.overrideResponse = { request in
            var headers = "Content-Type: text/html\r\nCache-Control: no-store\r\n"
            if request.path == "/seed" {
                headers += "Set-Cookie: hostOnly=fixture; Path=/; Secure; SameSite=None\r\n"
                headers +=
                    "Set-Cookie: domainCookie=fixture; Domain=parent.localhost; Path=/; Secure; SameSite=None\r\n"
                headers += "Set-Cookie: hostLax=fixture; Path=/; Secure; SameSite=Lax\r\n"
                headers += "Set-Cookie: domainLax=fixture; Domain=parent.localhost; Path=/; Secure; SameSite=Lax\r\n"
                headers += "Set-Cookie: insecureLax=fixture; Path=/; SameSite=Lax\r\n"
                headers += "Set-Cookie: hostStrict=fixture; Path=/; Secure; HttpOnly; SameSite=Strict\r\n"
                headers += "Set-Cookie: privatePath=fixture; Path=/private; Secure; SameSite=Lax\r\n"
                headers += "Set-Cookie: partitioned=fixture; Path=/; Secure; SameSite=None; Partitioned\r\n"
            }
            if request.path == "/rotate" {
                headers += "Set-Cookie: hostStrict=panel-only-refresh; Path=/; Secure; HttpOnly; SameSite=None\r\n"
            }
            if request.path == "/redirect-parent" {
                return (
                    "302 Found",
                    headers
                        + "Location: \(server.url(host: "parent.localhost", path: "/probe?stage=foreign-redirect-target"))\r\n",
                    Data()
                )
            }
            if request.path == "/redirect" {
                return (
                    "302 Found",
                    headers
                        + "Location: \(server.url(host: "child.parent.localhost", path: "/icon?stage=redirect-child"))\r\n",
                    Data()
                )
            }
            return ("200 OK", headers, Data("<!doctype html><title>Cookie fixture</title><body>Fixture</body>".utf8))
        }
        let storeID = UUID()
        let normal = persistent ? WKWebsiteDataStore(forIdentifier: storeID) : WKWebsiteDataStore.nonPersistent()
        if persistent {
            addTeardownBlock {
                for attempt in 0..<20 {
                    do {
                        try await WKWebsiteDataStore.remove(forIdentifier: storeID)
                        return
                    } catch { if attempt == 19 { throw error } }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        let navigation = ExtensionPrivacyNavigation(port: Int(server.port))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = normal
        let tab = WKWebView(frame: .zero, configuration: configuration)
        tab.navigationDelegate = navigation
        tab.load(URLRequest(url: server.url(host: "parent.localhost", path: "/seed")))
        try await wait { !tab.isLoading && tab.url?.path == "/seed" }
        let before = await normal.httpCookieStore.allCookies()
        XCTAssertEqual(before.first { $0.name == "hostOnly" }?.domain, "parent.localhost")
        XCTAssertEqual(before.first { $0.name == "domainCookie" }?.domain, ".parent.localhost")
        XCTAssertNotNil(
            before.first { $0.name == "partitioned" }?.properties?[HTTPCookiePropertyKey("StoragePartition")])

        let root = FileManager.default.temporaryDirectory.appending(path: "crest-extension-cookie-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest: [String: Any] = [
            "manifest_version": 3, "name": "Cookie scope fixture", "version": "1.0",
            "host_permissions": [persistent ? "<all_urls>" : "https://parent.localhost/*"],
            "permissions": ["storage"],
            "background": ["service_worker": "worker.js"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appending(path: "manifest.json"))
        try """
        browser.runtime.onMessage.addListener(async () => {
            const value = await browser.storage.local.get('panelMarker');
            await browser.storage.local.set({backgroundMarker:'native-background'});
            return {ready:true, marker:value.panelMarker};
        });
        """
        .write(to: root.appending(path: "worker.js"), atomically: true, encoding: .utf8)
        try "<!doctype html><title>Extension fixture</title><body>Panel</body>"
            .write(to: root.appending(path: "panel.html"), atomically: true, encoding: .utf8)
        let controllerConfiguration = WKWebExtensionController.Configuration.nonPersistent()
        controllerConfiguration.defaultWebsiteDataStore = normal
        let controller = WKWebExtensionController(configuration: controllerConfiguration)
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: root))
        context.hasAccessToPrivateData = !persistent
        let pattern = try WKWebExtension.MatchPattern(string: persistent ? "<all_urls>" : "https://parent.localhost/*")
        context.setPermissionStatus(.grantedExplicitly, for: pattern)
        context.setPermissionStatus(.grantedExplicitly, for: .storage)
        try controller.load(context)
        defer { try? controller.unload(context) }
        let panelConfiguration = try XCTUnwrap(context.webViewConfiguration)
        let frames = ExtensionPrivacyFrames()
        let document = BrowserExtensionSidebarDocument(
            url: context.baseURL.appending(path: "panel.html"), tabID: nil,
            configuration: .init(
                baseURL: context.baseURL, context: context, webViewConfiguration: panelConfiguration,
                clientID: .scoped(extensionID: "cookie-fixture", spaceID: SpaceID())),
            installRuntimeBridge: { content in
                content.add(frames, name: "cookieFixtureFrame")
                content.addUserScript(
                    WKUserScript(
                        source: "window.webkit.messageHandlers.cookieFixtureFrame.postMessage(location.href);",
                        injectionTime: .atDocumentEnd, forMainFrameOnly: false))
                return nil
            }, openTab: { _ in XCTFail("Cookie fixture must remain embedded") })
        defer { document.close() }
        let panel = try XCTUnwrap(document.webView)
        let hosted = panel.configuration.websiteDataStore
        XCTAssertFalse(hosted === normal)
        XCTAssertFalse(hosted.isPersistent)
        navigation.forward = document
        panel.navigationDelegate = navigation
        try await wait { !panel.isLoading && panel.url?.path == "/panel.html" }
        _ = try await panel.callAsyncJavaScript(
            """
            globalThis.backgroundChangeSeen = false;
            browser.storage.onChanged.addListener(changes => {
                if (changes.backgroundMarker) globalThis.backgroundChangeSeen = true;
            });
            await browser.storage.local.set({panelMarker:'native-panel'});
            """, arguments: [:], contentWorld: .page)
        let reply =
            try await panel.callAsyncJavaScript(
                "return await browser.runtime.sendMessage({ping:true});", arguments: [:], contentWorld: .page)
            as? [String: Any]
        XCTAssertEqual(reply?["ready"] as? Bool, true)
        XCTAssertEqual(reply?["marker"] as? String, "native-panel")
        let storageEvent =
            try await panel.callAsyncJavaScript(
                """
                for(let i=0;i<100 && !globalThis.backgroundChangeSeen;i++)
                    await new Promise(resolve=>setTimeout(resolve,25));
                return globalThis.backgroundChangeSeen;
                """, arguments: [:], contentWorld: .page) as? Bool
        XCTAssertEqual(storageEvent, true)
        func addFrame(host: String, stage: String, in parent: WKFrameInfo? = nil) async throws -> WKFrameInfo {
            let url = server.url(host: host, path: "/probe?stage=\(stage)")
            _ = try await panel.callAsyncJavaScript(
                "const f=document.createElement('iframe');f.src=url;document.body.append(f);",
                arguments: ["url": url.absoluteString], in: parent, contentWorld: .page)
            try await wait { frames.byURL[url.absoluteString] != nil }
            return try XCTUnwrap(frames.byURL[url.absoluteString])
        }
        let parent = try await addFrame(host: "parent.localhost", stage: "parent")
        XCTAssertTrue(
            server.requests.first { $0.query == "stage=parent" }?.headers["cookie"]?.contains("hostLax=") == true,
            "A permitted direct panel frame must authenticate without weakening the browser store")
        let scriptCookies =
            try await panel.callAsyncJavaScript(
                "return document.cookie;", arguments: [:], in: parent, contentWorld: .page) as? String ?? ""
        XCTAssertFalse(scriptCookies.contains("hostOnly="))
        XCTAssertFalse(scriptCookies.contains("hostLax="))
        XCTAssertFalse(scriptCookies.contains("hostStrict="))
        for path in [
            "/private/probe?stage=path-match", "/privateer/probe?stage=path-mismatch", "/redirect?stage=redirect",
        ] {
            _ = try await panel.callAsyncJavaScript(
                "return await fetch(url,{credentials:'include',mode:'no-cors'}).then(()=>true);",
                arguments: ["url": server.url(host: "parent.localhost", path: path).absoluteString], in: parent,
                contentWorld: .page)
        }
        for host in ["parent.localhost", "child.parent.localhost"] {
            let stage = host == "parent.localhost" ? "root-parent-fetch" : "root-child-fetch"
            _ = try await panel.callAsyncJavaScript(
                "return await fetch(url,{credentials:'include',mode:'no-cors'}).then(()=>true);",
                arguments: ["url": server.url(host: host, path: "/probe?stage=\(stage)").absoluteString],
                contentWorld: .page)
        }
        _ = try await addFrame(host: "child.parent.localhost", stage: "child")
        let foreign = try await addFrame(host: "other.localhost", stage: "foreign")
        let blocked = server.url(host: "parent.localhost", path: "/probe?stage=foreign-nested-parent")
        _ = try await panel.callAsyncJavaScript(
            "const f=document.createElement('iframe');f.src=url;document.body.append(f);",
            arguments: ["url": blocked.absoluteString], in: foreign, contentWorld: .page)
        try await wait { navigation.decisions[blocked.absoluteString] != nil }
        XCTAssertEqual(navigation.decisions[blocked.absoluteString], .cancel)
        _ = try await panel.callAsyncJavaScript(
            "return await fetch(url,{credentials:'include',mode:'no-cors'}).then(()=>true);",
            arguments: ["url": server.url(host: "parent.localhost", path: "/probe?stage=foreign-fetch").absoluteString],
            in: foreign, contentWorld: .page)
        XCTAssertFalse(server.requests.contains { $0.query == "stage=foreign-nested-parent" })
        let redirected = server.url(host: "parent.localhost", path: "/probe?stage=foreign-redirect-target")
        _ = try await panel.callAsyncJavaScript(
            "const f=document.createElement('iframe');f.src=url;document.body.append(f);",
            arguments: [
                "url": server.url(host: "other.localhost", path: "/redirect-parent?stage=foreign-redirect")
                    .absoluteString
            ],
            in: foreign, contentWorld: .page)
        try await wait {
            navigation.decisions[redirected.absoluteString] != nil || frames.byURL[redirected.absoluteString] != nil
        }
        XCTAssertEqual(navigation.decisions[redirected.absoluteString], .cancel)
        XCTAssertFalse(server.requests.contains { $0.query == "stage=foreign-redirect-target" })

        let requests = server.requests.filter { $0.query != nil }
        XCTAssertGreaterThanOrEqual(requests.count, 8)
        for request in requests {
            let cookies = request.headers["cookie", default: ""]
            if ["stage=parent", "stage=path-match", "stage=path-mismatch", "stage=redirect", "stage=root-parent-fetch"]
                .contains(request.query)
            {
                XCTAssertTrue(cookies.contains("hostLax="), request.description)
                XCTAssertTrue(cookies.contains("hostStrict="), request.description)
                XCTAssertTrue(cookies.contains("domainLax="), request.description)
            } else if persistent && request.query == "stage=child" {
                XCTAssertTrue(cookies.contains("domainLax="), request.description)
                XCTAssertFalse(cookies.contains("hostLax="), request.description)
                XCTAssertFalse(cookies.contains("hostStrict="), request.description)
            } else {
                XCTAssertTrue(cookies.isEmpty, request.description)
            }
            XCTAssertFalse(cookies.contains("insecureLax="), request.description)
            XCTAssertFalse(cookies.contains("partitioned="), request.description)
            if request.host.hasPrefix("child.") {
                XCTAssertFalse(cookies.contains("hostOnly="), request.description)
                XCTAssertFalse(cookies.contains("domainCookie="), request.description)
            }
            if !request.path.hasPrefix("/private/") {
                XCTAssertFalse(cookies.contains("privatePath="), request.description)
            }
        }
        XCTAssertTrue(
            requests.first { $0.query == "stage=path-match" }?.headers["cookie"]?.contains("privatePath=") == true)
        // A panel response may refresh its own session, but it cannot replace
        // the normal jar's credentials, cookie flags, or partition identity.
        _ = try await panel.callAsyncJavaScript(
            "return await fetch(url,{credentials:'include'}).then(()=>true);",
            arguments: ["url": server.url(host: "parent.localhost", path: "/rotate").absoluteString],
            in: parent, contentWorld: .page)
        try await wait {
            await hosted.httpCookieStore.allCookies().contains {
                $0.name == "hostStrict" && $0.value == "panel-only-refresh" && $0.sameSitePolicy != .sameSiteStrict
            }
        }
        let originalAfterRefresh = await normal.httpCookieStore.allCookies().first { $0.name == "hostStrict" }
        XCTAssertEqual(originalAfterRefresh?.value, "fixture")
        // The same original session remains usable as a first-party page.
        tab.load(URLRequest(url: server.url(host: "parent.localhost", path: "/probe?stage=first-party")))
        try await wait { server.requests.contains { $0.query == "stage=first-party" } }
        let authenticated = try XCTUnwrap(server.requests.first { $0.query == "stage=first-party" }?.headers["cookie"])
        XCTAssertTrue(authenticated.contains("hostLax=") && authenticated.contains("hostStrict="))
        let after = await normal.httpCookieStore.allCookies()
        XCTAssertEqual(after.first { $0.name == "hostLax" }?.sameSitePolicy, .sameSiteLax)
        XCTAssertEqual(after.first { $0.name == "hostStrict" }?.sameSitePolicy, .sameSiteStrict)

        if persistent {
            await normal.removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast)
        } else {
            context.setPermissionStatus(.deniedExplicitly, for: pattern)
        }
        try await wait { document.webView == nil }
        try await wait { await hosted.httpCookieStore.allCookies().isEmpty }
        let policy = await hosted.httpCookieStore.cookiePolicy
        XCTAssertEqual(policy, .disallow)
        _ = try await panel.callAsyncJavaScript(
            "return await fetch(url,{credentials:'include',mode:'no-cors'}).then(()=>true);",
            arguments: [
                "url": server.url(host: "parent.localhost", path: "/probe?stage=after-invalidation").absoluteString
            ],
            in: parent, contentWorld: .page)
        XCTAssertNil(server.requests.first { $0.query == "stage=after-invalidation" }?.headers["cookie"])

        let otherConfiguration = WKWebExtensionController.Configuration.nonPersistent()
        otherConfiguration.defaultWebsiteDataStore = .nonPersistent()
        let otherController = WKWebExtensionController(configuration: otherConfiguration)
        let otherContext = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: root))
        otherContext.hasAccessToPrivateData = true
        otherContext.setPermissionStatus(.grantedExplicitly, for: pattern)
        try otherController.load(otherContext)
        defer { try? otherController.unload(otherContext) }
        let otherDocument = BrowserExtensionSidebarDocument(
            url: otherContext.baseURL.appending(path: "panel.html"), tabID: nil,
            configuration: .init(
                baseURL: otherContext.baseURL, context: otherContext,
                webViewConfiguration: try XCTUnwrap(otherContext.webViewConfiguration),
                clientID: .scoped(extensionID: "cookie-fixture", spaceID: SpaceID())),
            openTab: { _ in XCTFail("The second Space must remain embedded") })
        defer { otherDocument.close() }
        let otherPanel = try XCTUnwrap(otherDocument.webView)
        let otherNavigation = ExtensionPrivacyNavigation(port: Int(server.port))
        otherNavigation.forward = otherDocument
        otherPanel.navigationDelegate = otherNavigation
        try await wait { !otherPanel.isLoading && otherPanel.url?.path == "/panel.html" }
        _ = try await otherPanel.callAsyncJavaScript(
            "const f=document.createElement('iframe');f.src=url;document.body.append(f);",
            arguments: ["url": server.url(host: "parent.localhost", path: "/probe?stage=other-space").absoluteString],
            contentWorld: .page)
        try await wait { server.requests.contains { $0.query == "stage=other-space" } }
        XCTAssertNil(server.requests.first { $0.query == "stage=other-space" }?.headers["cookie"])
        let attachment = XCTAttachment(string: server.requests.map(\.description).joined(separator: "\n"))
        attachment.name = "Scoped extension panel cookie wire requests"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(domain: "ExtensionPrivacyFixtureTimeout", code: 1)
    }
}
@MainActor
private final class ExtensionPrivacyFrames: NSObject, WKScriptMessageHandler {
    var byURL: [String: WKFrameInfo] = [:]
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let url = message.body as? String { byURL[url] = message.frameInfo }
    }
}
@MainActor
private final class ExtensionPrivacyNavigation: NSObject, WKNavigationDelegate {
    let port: Int
    weak var forward: BrowserExtensionSidebarDocument?
    var decisions: [String: WKNavigationActionPolicy] = [:]
    init(port: Int) { self.port = port }
    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if let forward, webView === forward.webView {
            forward.webView(
                webView, decidePolicyFor: action, preferences: preferences,
                decisionHandler: { [weak self] policy, preferences in
                    if let url = action.request.url { self?.decisions[url.absoluteString] = policy }
                    decisionHandler(policy, preferences)
                })
        } else {
            decisionHandler(.allow, preferences)
        }
    }
    func webView(
        _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if ["parent.localhost", "child.parent.localhost", "other.localhost"].contains(challenge.protectionSpace.host),
            challenge.protectionSpace.port == port, let trust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
