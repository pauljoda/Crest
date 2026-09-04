import WebKit
import XCTest

@testable import Crest

/// A real, disposable inspected page for the CDP domain translators.
///
/// Every domain is tested against WebKit itself rather than a recorded
/// transcript: the translations exist precisely because WebKit's shapes differ
/// from Chrome's, and a fake would be written from the same reading of the
/// specification that the translation was.
@MainActor
final class BrowserChromeDebuggerDomainFixture {
    let page: WKWebView
    let connection: BrowserWebInspectorProtocolConnection
    let target = BrowserExtensionDebuggerTarget(spaceID: SpaceID(), tabID: TabID())
    private(set) var events: [(method: String, parameters: [String: Any])] = []
    private var window: NSWindow?
    private var directory: URL?

    private init(
        page: WKWebView, connection: BrowserWebInspectorProtocolConnection, window: NSWindow?, directory: URL?
    ) {
        self.page = page
        self.connection = connection
        self.window = window
        self.directory = directory
    }

    /// `navigable` loads the page from a real file URL instead of an HTML
    /// string. Reload and navigation are only observable on a document WebKit
    /// can actually fetch again, and a string-loaded page has no such document.
    static func make(
        html: String = "<!doctype html><title>Crest domain test</title>", hosted: Bool = false,
        navigable: Bool = false, uiDelegate: (any WKUIDelegate)? = nil
    ) async throws -> BrowserChromeDebuggerDomainFixture {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences)
        let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        page.isInspectable = true
        page.uiDelegate = uiDelegate
        var window: NSWindow?
        if hosted {
            // Input needs a key window: WebKit decides a page is focused from
            // its window, and an unfocused page routes no keystrokes. The
            // window sits far off every display, so nothing is shown.
            let hostWindow = NSWindow(
                contentRect: CGRect(x: -20000, y: -20000, width: 640, height: 480),
                styleMask: [.borderless], backing: .buffered, defer: false)
            hostWindow.isReleasedWhenClosed = false
            hostWindow.contentView?.addSubview(page)
            hostWindow.orderFrontRegardless()
            hostWindow.makeKey()
            hostWindow.makeFirstResponder(page)
            window = hostWindow
        }
        var directory: URL?
        if navigable {
            let root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("crest-debugger-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            directory = root
            let start = root.appendingPathComponent("start.html")
            try Data(html.utf8).write(to: start)
            page.loadFileURL(start, allowingReadAccessTo: root)
        } else {
            page.loadHTMLString(html, baseURL: URL(string: "https://crest.test/domain"))
        }
        try await waitFor(seconds: 10) {
            (try? await page.evaluateJavaScript("document.readyState")) as? String == "complete"
        }
        let connection = BrowserWebInspectorProtocolConnection(webView: page)
        try await connection.connect()
        return BrowserChromeDebuggerDomainFixture(
            page: page, connection: connection, window: window, directory: directory)
    }

    /// Writes another document the page can really navigate to.
    func writePage(named name: String, html: String) throws -> URL {
        let directory = try XCTUnwrap(directory, "This fixture was not made navigable.")
        let url = directory.appendingPathComponent(name)
        try Data(html.utf8).write(to: url)
        return url
    }

    /// Routes engine events the way the session store does, so the fan-out the
    /// translators rely on is the one under test.
    func route(_ receivers: [(String, [String: Any]) -> Void]) {
        connection.onEvent = { method, parameters in
            for receive in receivers { receive(method, parameters) }
        }
    }

    func record(_ method: String, _ parameters: [String: Any]) {
        events.append((method, parameters))
    }

    func recorder() -> (String, [String: Any]) -> Void {
        { [weak self] method, parameters in self?.record(method, parameters) }
    }

    func first(_ method: String) -> [String: Any]? {
        events.first { $0.method == method }?.parameters
    }

    func all(_ method: String) -> [[String: Any]] {
        events.filter { $0.method == method }.map(\.parameters)
    }

    func tearDown() {
        connection.onEvent = nil
        connection.disconnect()
        page.stopLoading()
        page.removeFromSuperview()
        window?.close()
        window = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    func waitForEvent(_ method: String, where predicate: @escaping ([String: Any]) -> Bool = { _ in true }) async throws
    {
        try await Self.waitFor(seconds: 10) { [weak self] in
            self?.all(method).contains(where: predicate) == true
        }
    }

    static func waitFor(seconds: Int = 5, _ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while try await !condition() {
            guard ContinuousClock.now < deadline else { throw BrowserWebInspectorProtocolError.timedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

/// A page that offers its dialogs to a debugger session exactly the way
/// `BrowserPage` does, without the rest of a real page's dependencies.
@MainActor
final class BrowserChromeDebuggerDialogPage: NSObject, WKUIDelegate, BrowserExtensionDebuggerDialogHosting {
    var debuggerDialogInterceptor: BrowserExtensionDebuggerDialogInterceptor?
    private(set) var presentedByCrest: [String] = []

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        guard
            !intercept(
                .alert, message: message, defaultPrompt: nil, frame: frame,
                resolve: { _, _ in
                    completionHandler()
                })
        else { return }
        presentedByCrest.append(message)
        completionHandler()
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        guard
            !intercept(
                .confirm, message: message, defaultPrompt: nil, frame: frame,
                resolve: { accept, _ in
                    completionHandler(accept)
                })
        else { return }
        presentedByCrest.append(message)
        completionHandler(false)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        guard
            !intercept(
                .prompt, message: prompt, defaultPrompt: defaultText ?? "", frame: frame,
                resolve: { _, text in completionHandler(text) })
        else { return }
        presentedByCrest.append(prompt)
        completionHandler(nil)
    }

    private func intercept(
        _ kind: BrowserExtensionDebuggerDialogKind, message: String, defaultPrompt: String?, frame: WKFrameInfo,
        resolve: @escaping (Bool, String?) -> Void
    ) -> Bool {
        guard let debuggerDialogInterceptor else { return false }
        return debuggerDialogInterceptor.intercept(
            BrowserExtensionDebuggerDialog(
                kind: kind, message: message, defaultPrompt: defaultPrompt, url: frame.request.url),
            resolve: resolve)
    }
}

/// Records the tab operations `Page.close`, `Page.bringToFront`, and
/// `Target.closeTarget` route out of the protocol.
@MainActor
final class BrowserChromeDebuggerTabHostDouble: BrowserExtensionDebuggerTabHosting {
    private(set) var activated: [BrowserExtensionDebuggerTarget] = []
    private(set) var closed: [BrowserExtensionDebuggerTarget] = []

    func debuggerActivateTab(for target: BrowserExtensionDebuggerTarget) async throws {
        activated.append(target)
    }

    func debuggerCloseTab(for target: BrowserExtensionDebuggerTarget) async throws {
        closed.append(target)
    }
}
