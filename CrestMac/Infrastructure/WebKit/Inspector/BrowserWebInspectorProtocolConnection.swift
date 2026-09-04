import Foundation
import WebKit

enum BrowserWebInspectorProtocolError: Error, Equatable, LocalizedError {
    case unavailable
    case alreadyConnected
    case notConnected
    case timedOut
    case invalidResponse
    /// The frontend a previous attachment asked this inspector to close is still
    /// the one WebKit reports, so attaching now would bind to a page that is
    /// about to be destroyed.
    case closingInProgress

    var errorDescription: String? {
        switch self {
        case .unavailable: "This page does not expose an inspectable engine connection."
        case .alreadyConnected: "Another client is already connected to this page's Inspector."
        case .notConnected: "This Inspector connection is not attached to a page."
        case .timedOut: "The Inspector frontend did not become ready in time."
        case .invalidResponse: "The Inspector returned a response Crest could not read."
        case .closingInProgress: "The Inspector frontend of the previous attachment is still closing."
        }
    }
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
    private var claimedAttachment: UUID?
    private let messageName = "crestInspectorProtocol_" + UUID().uuidString

    /// The `_WKInspector` belongs to the inspected web view rather than to a
    /// connection, and its `close` only starts the teardown: the frontend page
    /// stays loaded and keeps answering script evaluation until a later
    /// `connect` replaces it. A new attachment must not bind to that outgoing
    /// page, whose teardown fails whatever script call is already in flight.
    /// The record is shared because the attachment that reconnects is often a
    /// different connection object: the extension session store builds one for
    /// every `chrome.debugger` attach.
    private static var pendingCloses: [ObjectIdentifier: PendingClose] = [:]

    private struct PendingClose {
        weak var inspector: NSObject?
        weak var frontend: WKWebView?
        /// Identifies the mark the closed attachment left on its frontend page,
        /// so a later attachment can tell that page apart from its replacement.
        let attachment: UUID?
    }

    private enum FrontendClaim {
        case notReady
        case retired
        case claimed
    }

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
        let pending = Self.pendingClose(for: candidate)
        if let pending { try await Self.waitForClose(pending, in: candidate) }
        guard !Self.boolean("isConnected", from: candidate) else {
            throw BrowserWebInspectorProtocolError.alreadyConnected
        }
        let attachmentID = UUID()
        self.attachmentID = attachmentID
        inspector = candidate
        candidate.perform(NSSelectorFromString("connect"))
        do {
            let readyFrontend = try await waitForFrontend(
                in: candidate, attachmentID: attachmentID, replacing: pending?.attachment)
            try Task.checkCancellation()
            guard self.attachmentID == attachmentID else { throw BrowserWebInspectorProtocolError.notConnected }
            Self.pendingCloses[ObjectIdentifier(candidate)] = nil
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
        let ownedClaim = claimedAttachment
        inspector = nil
        frontend = nil
        attachmentID = nil
        claimedAttachment = nil
        ownedFrontend?.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        guard let ownedInspector else { return }
        if let ownedFrontend,
            Self.object("inspectorWebView", from: ownedInspector) !== ownedFrontend
        {
            // The user closed our session and opened a different Inspector.
            return
        }
        // Record what this close leaves behind before asking for it, because the
        // next attachment has to outlast the teardown rather than race it. An
        // attachment that never claimed a page keeps the mark of the one that
        // did, so a stalled teardown stays recognizable across retries.
        let close = PendingClose(
            inspector: ownedInspector,
            frontend: Self.object("inspectorWebView", from: ownedInspector) as? WKWebView,
            attachment: ownedClaim ?? Self.pendingClose(for: ownedInspector)?.attachment)
        Self.pendingCloses = Self.pendingCloses.filter { $0.value.inspector != nil }
        Self.pendingCloses[ObjectIdentifier(ownedInspector)] = close
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

    private func waitForFrontend(
        in candidate: NSObject, attachmentID: UUID, replacing retiredAttachment: UUID?
    ) async throws -> WKWebView {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        var sawRetiredFrontend = false
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard self.attachmentID == attachmentID else { throw BrowserWebInspectorProtocolError.notConnected }
            if let view = Self.object("inspectorWebView", from: candidate) as? WKWebView {
                switch await Self.claim(view, for: attachmentID, replacing: retiredAttachment) {
                case .claimed:
                    guard self.attachmentID == attachmentID else {
                        throw BrowserWebInspectorProtocolError.notConnected
                    }
                    claimedAttachment = attachmentID
                    return view
                case .retired: sawRetiredFrontend = true
                case .notReady: break
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw sawRetiredFrontend
            ? BrowserWebInspectorProtocolError.closingInProgress
            : BrowserWebInspectorProtocolError.timedOut
    }

    /// Marks the frontend page as this attachment's before any command runs.
    /// The mark lives on the page's own global object, so the page WebKit is
    /// still retiring keeps the previous attachment's mark and is skipped,
    /// while its replacement starts unmarked. Claiming through
    /// `callAsyncJavaScript` also proves the page can still service the call
    /// the bootstrap is about to make: a page mid-teardown throws instead,
    /// which reads as "not ready yet" and is retried.
    private static func claim(
        _ frontend: WKWebView, for attachmentID: UUID, replacing retiredAttachment: UUID?
    ) async -> FrontendClaim {
        let outcome = try? await frontend.callAsyncJavaScript(
            """
            if (typeof InspectorBackend === 'undefined' || !globalThis.WI?.pageTarget?.RuntimeAgent) {
                return 'notReady';
            }
            if (retired !== null && globalThis.crestInspectorAttachment === retired) { return 'retired'; }
            globalThis.crestInspectorAttachment = attachment;
            return 'claimed';
            """,
            arguments: [
                "attachment": attachmentID.uuidString,
                "retired": retiredAttachment?.uuidString as Any? ?? NSNull(),
            ], contentWorld: .page)
        switch outcome as? String {
        case "claimed": return .claimed
        case "retired": return .retired
        default: return .notReady
        }
    }

    private static func pendingClose(for inspector: NSObject) -> PendingClose? {
        guard let pending = pendingCloses[ObjectIdentifier(inspector)] else { return nil }
        // A released inspector can leave its address to a new one.
        guard pending.inspector === inspector else {
            pendingCloses[ObjectIdentifier(inspector)] = nil
            return nil
        }
        return pending
    }

    /// Holds a new attachment back until the inspector itself has let go of the
    /// frontend a previous `close` retired. The inspector clears its own state
    /// well before WebKit finishes with that page, so this only closes the
    /// narrow window before the request is applied; `waitForFrontend` covers
    /// the page that outlives it.
    private static func waitForClose(_ pending: PendingClose, in inspector: NSObject) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            try Task.checkCancellation()
            let current = object("inspectorWebView", from: inspector) as? WKWebView
            let retired = pending.frontend == nil || current !== pending.frontend
            // A session reported while some other frontend is attached belongs
            // to the user's own Inspector, which `connect` rejects as
            // `alreadyConnected` rather than waiting out.
            if retired, !boolean("isConnected", from: inspector) || current != nil { return }
            guard ContinuousClock.now < deadline else {
                throw BrowserWebInspectorProtocolError.closingInProgress
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }
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
