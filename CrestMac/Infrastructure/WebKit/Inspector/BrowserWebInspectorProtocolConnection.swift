import Foundation
import WebKit

enum BrowserWebInspectorProtocolError: Error, Equatable {
    case unavailable
    case alreadyConnected
    case notConnected
    case timedOut
    case invalidResponse
}

/// A connection to WebKit's own protocol, not Chrome DevTools Protocol.
/// Callers must translate commands and authorize the inspected page separately.
/// This transport is not exposed to extensions until that integration is ready.
@MainActor
final class BrowserWebInspectorProtocolConnection {
    var onEvent: ((String, [String: Any]) -> Void)?
    /// Rechecked for every native command, including multi-command translations
    /// that suspend between operations. This never grants access by itself.
    var authorizeCommand: (() throws -> Void)?

    var isConnected: Bool {
        guard let frontend, let inspector else { return false }
        return Self.boolean("isConnected", from: inspector)
            && Self.object("inspectorWebView", from: inspector) === frontend
    }

    var attachmentIdentifier: UUID? { isConnected ? attachmentID : nil }

    private weak var webView: WKWebView?
    private var inspector: NSObject?
    private var frontend: WKWebView?
    private var attachmentID: UUID?
    private let messageName = "crestInspectorProtocol_" + UUID().uuidString

    init(webView: WKWebView) {
        self.webView = webView
    }

    isolated deinit {
        disconnect()
    }

    func connect() async throws {
        guard inspector == nil else { throw BrowserWebInspectorProtocolError.alreadyConnected }
        guard let webView, webView.isInspectable,
            let candidate = Self.object("_inspector", from: webView),
            candidate.responds(to: NSSelectorFromString("connect")),
            candidate.responds(to: NSSelectorFromString("close")),
            candidate.responds(to: NSSelectorFromString("inspectorWebView"))
        else { throw BrowserWebInspectorProtocolError.unavailable }
        guard !Self.boolean("isConnected", from: candidate) else {
            throw BrowserWebInspectorProtocolError.alreadyConnected
        }
        let attachmentID = UUID()
        self.attachmentID = attachmentID
        inspector = candidate
        candidate.perform(NSSelectorFromString("connect"))
        do {
            let readyFrontend = try await waitForFrontend(in: candidate, attachmentID: attachmentID)
            try Task.checkCancellation()
            guard self.attachmentID == attachmentID else { throw BrowserWebInspectorProtocolError.notConnected }
            frontend = readyFrontend
            readyFrontend.configuration.userContentController.add(
                BrowserWebInspectorProtocolMessageHandler(connection: self), name: messageName)
            _ = try await readyFrontend.callAsyncJavaScript(
                """
                const connection = WI.pageTarget.connection;
                const originalDispatch = connection.dispatch;
                connection.dispatch = function(message) {
                    const event = typeof message === 'string' ? JSON.parse(message) : message;
                    if (event.method && !Object.hasOwn(event, 'id')) {
                        globalThis.webkit?.messageHandlers?.[messageName]?.postMessage({
                            method: event.method, parameters: event.params ?? {}
                        });
                    }
                    return Reflect.apply(originalDispatch, this, arguments);
                };
                """, arguments: ["messageName": messageName], contentWorld: .page)
        } catch {
            if self.attachmentID == attachmentID { disconnect() }
            throw error
        }
    }

    func sendCommand(_ method: String, parameters: [String: Any] = [:]) async throws -> [String: Any] {
        try authorizeCommand?()
        guard isConnected, let frontend
        else { throw BrowserWebInspectorProtocolError.notConnected }
        let result = try await frontend.callAsyncJavaScript(
            """
            if (!InspectorBackend.hasCommand(method)) {
                throw new Error('WebKit does not support the protocol command: ' + method);
            }
            const target = WI.pageTarget;
            const [domain, name] = method.split('.');
            const command = target?.[domain + 'Agent']?.[name];
            if (typeof command?.invoke !== 'function') {
                throw new Error('The inspected target does not support: ' + method);
            }
            for (const name of Object.keys(parameters)) {
                if (!target.hasCommand(method, name)) {
                    throw new Error('WebKit does not support the protocol parameter: ' + method + '.' + name);
                }
            }
            return JSON.stringify(await command.invoke(parameters));
            """, arguments: ["method": method, "parameters": parameters], contentWorld: .page)
        guard let json = result as? String,
            let response = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else { throw BrowserWebInspectorProtocolError.invalidResponse }
        return response
    }

    func observeExecutionContexts(subscription: UUID?) async throws {
        try authorizeCommand?()
        guard isConnected, let frontend
        else { throw BrowserWebInspectorProtocolError.notConnected }
        _ = try await frontend.callAsyncJavaScript(
            BrowserWebInspectorExecutionContextScript.source,
            arguments: ["messageName": messageName, "subscription": subscription?.uuidString as Any? ?? NSNull()],
            contentWorld: .page)
    }

    func disconnect() {
        let ownedInspector = inspector
        let ownedFrontend = frontend
        inspector = nil
        frontend = nil
        attachmentID = nil
        ownedFrontend?.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        guard let ownedInspector else { return }
        if let ownedFrontend,
            Self.object("inspectorWebView", from: ownedInspector) !== ownedFrontend
        {
            // The user closed our session and opened a different Inspector.
            return
        }
        ownedInspector.perform(NSSelectorFromString("close"))
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === frontend,
            let event = message.body as? [String: Any],
            let method = event["method"] as? String,
            let parameters = event["parameters"] as? [String: Any]
        else { return }
        onEvent?(method, parameters)
    }

    private func waitForFrontend(in candidate: NSObject, attachmentID: UUID) async throws -> WKWebView {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard self.attachmentID == attachmentID else { throw BrowserWebInspectorProtocolError.notConnected }
            if let view = Self.object("inspectorWebView", from: candidate) as? WKWebView,
                (try? await view.evaluateJavaScript(
                    "typeof InspectorBackend !== 'undefined' && !!globalThis.WI?.pageTarget?.RuntimeAgent"
                )) as? Bool == true
            {
                return view
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw BrowserWebInspectorProtocolError.timedOut
    }

    private static func object(_ name: String, from owner: NSObject) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard owner.responds(to: selector) else { return nil }
        return owner.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    private static func boolean(_ name: String, from owner: NSObject) -> Bool {
        let selector = NSSelectorFromString(name)
        guard owner.responds(to: selector) else { return false }
        let getter = unsafeBitCast(
            owner.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        return getter(owner, selector)
    }
}

@MainActor
private final class BrowserWebInspectorProtocolMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var connection: BrowserWebInspectorProtocolConnection?

    init(connection: BrowserWebInspectorProtocolConnection) {
        self.connection = connection
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        connection?.receive(message)
    }
}
