import Foundation
import WebKit

/// Converts supported CDP `Page` operations to WebKit's protocol, plus the two
/// things WebKit's protocol cannot express: navigating and closing a Crest tab.
///
/// `Page.disable` never disables WebKit's own domain. Inspector bootstrapped it
/// for the frontend this transport borrows, so a client's disable only stops
/// Crest forwarding events, exactly as `Runtime.disable` already does.
@MainActor
final class BrowserChromeDebuggerPage {
    var onEvent: ((String, [String: Any]) -> Void)?

    private let connection: BrowserWebInspectorProtocolConnection
    private let target: BrowserExtensionDebuggerTarget
    private weak var webView: WKWebView?
    private weak var tabHost: (any BrowserExtensionDebuggerTabHosting)?
    private let dialogs = BrowserExtensionDebuggerDialogInterceptor()
    private var enabledAttachment: UUID?
    private var mainFrameID = ""

    private var isEnabled: Bool {
        enabledAttachment != nil && enabledAttachment == connection.attachmentIdentifier
    }

    init(
        connection: BrowserWebInspectorProtocolConnection, target: BrowserExtensionDebuggerTarget,
        webView: WKWebView, tabHost: (any BrowserExtensionDebuggerTabHosting)?
    ) {
        self.connection = connection
        self.target = target
        self.webView = webView
        self.tabHost = tabHost
        dialogs.frameIdentifier = { [weak self] in self?.mainFrameID ?? "" }
    }

    func execute(_ method: String, parameters: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard connection.isConnected else { throw BrowserWebInspectorProtocolError.notConnected }
        switch method {
        case "Page.enable":
            try await enable()
            return [:]
        case "Page.disable":
            detach()
            return [:]
        case "Page.getFrameTree":
            return ["frameTree": try await frameTree()]
        case "Page.navigate":
            return try await navigate(parameters)
        case "Page.reload":
            return try await reload(parameters)
        case "Page.bringToFront":
            guard let tabHost else { throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method) }
            try await tabHost.debuggerActivateTab(for: target)
            return [:]
        case "Page.close":
            return try await close(method)
        case "Page.handleJavaScriptDialog":
            return try handleDialog(parameters)
        default:
            throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method)
        }
    }

    func receive(_ method: String, parameters: [String: Any]) {
        guard isEnabled, method == "Page.frameNavigated",
            let frame = parameters["frame"] as? [String: Any]
        else { return }
        if frame["parentId"] == nil, let id = frame["id"] as? String { mainFrameID = id }
        onEvent?("Page.frameNavigated", ["frame": chromeFrame(frame), "type": "Navigation"])
    }

    /// Ends the session's hold on the page: no more events, and any dialog the
    /// page is blocked on is dismissed as a rejection rather than left waiting.
    func detach() {
        enabledAttachment = nil
        // Cancelled before the listener goes: a client that is still there,
        // because it disabled the domain rather than detached, is owed the
        // close event for the dialog it was about to answer.
        dialogs.cancelAll()
        dialogs.onEvent = nil
        if let host = dialogHost(), host.debuggerDialogInterceptor === dialogs {
            host.debuggerDialogInterceptor = nil
        }
    }

    /// Closing the tab is the same removal path `tabs.remove` uses, so a target
    /// the tab API would refuse is refused here too.
    private func close(_ method: String) async throws -> [String: Any] {
        guard let tabHost else { throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method) }
        detach()
        try await tabHost.debuggerCloseTab(for: target)
        return [:]
    }

    private func enable() async throws {
        guard let attachment = connection.attachmentIdentifier else {
            throw BrowserWebInspectorProtocolError.notConnected
        }
        if enabledAttachment != attachment {
            do {
                _ = try await connection.sendCommand("Page.enable")
            } catch {
                // Unlike Console and Network, WebKit's Page agent rejects a
                // second enable outright — and Inspector always enabled it while
                // bootstrapping the frontend this transport borrows. Rather than
                // read that refusal out of an error message, ask the domain to
                // answer: a live Page agent is the only thing that can.
                guard (try? await mainFrame()) != nil else { throw error }
            }
            enabledAttachment = attachment
        }
        mainFrameID = (try? await mainFrame()["id"] as? String) ?? mainFrameID
        dialogs.onEvent = { [weak self] method, parameters in self?.onEvent?(method, parameters) }
        dialogHost()?.debuggerDialogInterceptor = dialogs
    }

    private func handleDialog(_ parameters: [String: Any]) throws -> [String: Any] {
        let accept = try BrowserChromeDebuggerValues.boolean("accept", in: parameters)
        var promptText: String?
        if let value = parameters["promptText"] {
            guard let text = value as? String else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("promptText")
            }
            promptText = text
        }
        guard dialogs.handle(accept: accept, promptText: promptText) else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("No dialog is showing")
        }
        return [:]
    }

    private func navigate(_ parameters: [String: Any]) async throws -> [String: Any] {
        guard let raw = parameters["url"] as? String, let url = URL(string: raw), url.scheme != nil else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("url")
        }
        guard url.scheme?.lowercased() != "javascript" else {
            // Navigating to script would run page code outside every constraint
            // `Runtime.evaluate` enforces. Chrome refuses this too.
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter("url")
        }
        for name in ["transitionType", "referrer", "referrerPolicy"] where parameters[name] != nil {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter(name)
        }
        let frame = try await mainFrame()
        let frameID = frame["id"] as? String ?? mainFrameID
        if let requested = parameters["frameId"] as? String, requested != frameID {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter("frameId")
        }
        mainFrameID = frameID
        let previousLoader = frame["loaderId"] as? String
        guard let webView else { throw BrowserWebInspectorProtocolError.notConnected }
        webView.load(URLRequest(url: url))
        var result: [String: Any] = ["frameId": frameID]
        if let loaderID = try await loaderIdentifier(after: previousLoader) { result["loaderId"] = loaderID }
        return result
    }

    /// Chrome answers `navigate` with the document the navigation started.
    /// WebKit mints that loader identity asynchronously, so the reply waits
    /// briefly for it and otherwise reports the loader still in place.
    private func loaderIdentifier(after previous: String?) async throws -> String? {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(1500))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(25))
            guard let loaderID = try? await mainFrame()["loaderId"] as? String else { continue }
            if loaderID != previous { return loaderID }
        }
        return previous
    }

    private func reload(_ parameters: [String: Any]) async throws -> [String: Any] {
        for name in ["scriptToEvaluateOnLoad", "loaderId"] where parameters[name] != nil {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter(name)
        }
        var request: [String: Any] = [:]
        if parameters["ignoreCache"] != nil {
            request["ignoreCache"] = try BrowserChromeDebuggerValues.boolean("ignoreCache", in: parameters)
        }
        _ = try await connection.sendCommand("Page.reload", parameters: request)
        return [:]
    }

    private func frameTree() async throws -> [String: Any] {
        let response = try await connection.sendCommand("Page.getResourceTree")
        guard let tree = response["frameTree"] as? [String: Any] else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        return chromeTree(tree)
    }

    private func mainFrame() async throws -> [String: Any] {
        let response = try await connection.sendCommand("Page.getResourceTree")
        guard let tree = response["frameTree"] as? [String: Any], let frame = tree["frame"] as? [String: Any] else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        return frame
    }

    /// Drops WebKit's per-frame resource inventory: Chrome's frame tree carries
    /// frames only, and the resource list is a different domain's answer.
    private func chromeTree(_ tree: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        if let frame = tree["frame"] as? [String: Any] { result["frame"] = chromeFrame(frame) }
        if let children = tree["childFrames"] as? [[String: Any]], !children.isEmpty {
            result["childFrames"] = children.map(chromeTree)
        }
        return result
    }

    private func chromeFrame(_ webkit: [String: Any]) -> [String: Any] {
        let url = webkit["url"] as? String ?? ""
        var frame: [String: Any] = [
            "id": webkit["id"] as? String ?? "",
            "loaderId": webkit["loaderId"] as? String ?? "",
            "url": url,
            "securityOrigin": webkit["securityOrigin"] as? String ?? "",
            "mimeType": webkit["mimeType"] as? String ?? "",
            // Chrome derives this from a public suffix list Crest does not
            // carry. An empty value is what Chrome itself reports for a frame
            // with no registrable domain, and no client can read a wrong one.
            "domainAndRegistry": "",
            "secureContextType": secureContextType(url),
            "crossOriginIsolatedContextType": "NotIsolated",
            "gatedAPIFeatures": [],
        ]
        if let parentID = webkit["parentId"] as? String { frame["parentId"] = parentID }
        if let name = webkit["name"] as? String { frame["name"] = name }
        return frame
    }

    private func secureContextType(_ url: String) -> String {
        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased() else {
            return "InsecureScheme"
        }
        if ["https", "wss", "file", "data", "about"].contains(scheme) { return "Secure" }
        if ["localhost", "127.0.0.1", "::1"].contains(components.host ?? "") { return "SecureLocalhost" }
        return "InsecureScheme"
    }

    private func dialogHost() -> (any BrowserExtensionDebuggerDialogHosting)? {
        webView?.uiDelegate as? any BrowserExtensionDebuggerDialogHosting
    }
}
