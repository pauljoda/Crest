import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionNativeNamespaceTests: XCTestCase {
    func testModuleWorkerPublishesNotificationsAndKeepsNativeMessagingAlive() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-namespace-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest: [String: Any] = [
            "manifest_version": 3, "name": "Native namespace fixture", "version": "1.0",
            "description": "Tests prepared native module worker APIs.",
            "permissions": ["notifications", "nativeMessaging"],
            "background": ["service_worker": "worker.js", "type": "module"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appending(path: "manifest.json"))
        try "<html><body>Native namespace fixture</body></html>".write(
            to: root.appending(path: "probe.html"), atomically: true, encoding: .utf8)
        try """
        browser.runtime.onMessage.addListener((message, sender, reply) => {
            reply({
                notificationListener: typeof chrome.notifications?.onClicked?.addListener,
                notificationCreate: typeof chrome.notifications?.create,
                nativeMessaging: typeof chrome.runtime?.connectNative,
                sameRoot: chrome === browser
            });
            return false;
        });
        """.write(to: root.appending(path: "worker.js"), atomically: true, encoding: .utf8)
        let identity = BrowserExtensionRuntimeIdentity(
            extensionID: "namespace-fixture", uniqueIdentifier: UUID().uuidString,
            baseURL: URL(string: "chrome-extension://namespace-fixture/")!)
        _ = try BrowserChromeWebStoreCompatibilityPackagePreparer().installCompatibilityLayer(
            in: root, requestedPermissions: ["notifications", "nativeMessaging"], runtimeIdentity: identity)
        let configuration = WKWebExtensionController.Configuration.nonPersistent()
        let dataStore = WKWebsiteDataStore.nonPersistent()
        configuration.defaultWebsiteDataStore = dataStore
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = dataStore
        configuration.webViewConfiguration = webConfiguration
        let controller = WKWebExtensionController(configuration: configuration)
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: root))
        context.baseURL = identity.baseURL
        context.uniqueIdentifier = identity.uniqueIdentifier
        context.unsupportedAPIs = BrowserExtensionAPICompatibilityMatrix.unsupportedWebKitAPIs(
            requestedPermissions: ["notifications", "nativeMessaging"])
        context.hasAccessToPrivateData = true
        context.setPermissionStatus(.grantedExplicitly, for: .init(rawValue: "nativeMessaging"))
        try controller.load(context)
        defer { try? controller.unload(context) }
        let page = WKWebView(
            frame: .init(x: 0, y: 0, width: 300, height: 200),
            configuration: try XCTUnwrap(context.webViewConfiguration))
        page.load(URLRequest(url: identity.baseURL.appending(path: "probe.html")))
        defer { page.stopLoading() }
        try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
            (try? await page.evaluateJavaScript("document.readyState")) as? String == "complete"
                && page.url?.path == "/probe.html"
        }
        var report: [String: Any]?
        try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
            report =
                try? await page.callAsyncJavaScript(
                    "return await browser.runtime.sendMessage({probe:true});", arguments: [:], in: nil,
                    contentWorld: .page)
                as? [String: Any]
            return report != nil
        }
        let unwrappedReport = try XCTUnwrap(
            report, "Worker errors: \(context.errors.map { ($0 as NSError).description })")
        XCTAssertEqual(unwrappedReport["notificationListener"] as? String, "function")
        XCTAssertEqual(unwrappedReport["notificationCreate"] as? String, "function")
        XCTAssertEqual(unwrappedReport["nativeMessaging"] as? String, "function")
        XCTAssertEqual(unwrappedReport["sameRoot"] as? Bool, true)
    }
}
