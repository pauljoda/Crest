import Foundation
import WebKit

/// Binds one resident web view to the profile-owned Media Session store.
///
/// The coordinator accepts only main-frame messages authored by its exact web
/// view and only after that view commits the matching document URL. Navigation,
/// process loss, and page teardown all invalidate the endpoint before another
/// document is allowed to publish.
@MainActor
final class BrowserMediaSessionPageCoordinator {
    private weak var webView: WKWebView?
    private weak var endpoint: (any BrowserMediaSessionCommandEndpoint)?
    private let store: BrowserMediaSessionStore
    private let owner: @MainActor () -> BrowserTabRuntimeAssignment?
    private let fallbackTitle: @MainActor () -> String?
    private var acceptsEvents = false

    init(
        webView: WKWebView,
        endpoint: any BrowserMediaSessionCommandEndpoint,
        store: BrowserMediaSessionStore,
        owner: @escaping @MainActor () -> BrowserTabRuntimeAssignment?,
        fallbackTitle: @escaping @MainActor () -> String?
    ) {
        self.webView = webView
        self.endpoint = endpoint
        self.store = store
        self.owner = owner
        self.fallbackTitle = fallbackTitle
    }

    func prepareForNavigation() {
        invalidate()
        acceptsEvents = false
    }

    func didCommitNavigation() {
        acceptsEvents = true
    }

    func didFinishNavigation() {
        emitCurrentState()
    }

    /// A custom tab rename is Crest state rather than page Media Session state.
    /// Ask the same bounded bridge for a fresh sequenced event so the shared
    /// store can publish the new owner title without creating another truth.
    func ownerTitleDidChange() {
        emitCurrentState()
    }

    private func emitCurrentState() {
        guard acceptsEvents, let webView else { return }
        Task { @MainActor [weak webView] in
            _ = try? await webView?.callAsyncJavaScript(
                "return globalThis.__crestMediaSessionBridge?.emit();",
                arguments: [:],
                in: nil,
                contentWorld: BrowserMediaSessionContentBridge.contentWorld
            )
        }
    }

    func webContentProcessDidTerminate() {
        invalidate()
        acceptsEvents = false
    }

    func prepareForRemoval() {
        invalidate()
        acceptsEvents = false
        webView = nil
        endpoint = nil
    }

    func receive(_ message: WKScriptMessage) {
        guard acceptsEvents,
            message.frameInfo.isMainFrame,
            let webView,
            message.webView === webView,
            let endpoint,
            let owner = owner(),
            let event = BrowserMediaSessionPageEventDecoder.decode(message.body),
            event.location == webView.url?.absoluteString
        else { return }
        store.receive(
            event,
            owner: owner,
            fallbackTitle: fallbackTitle(),
            endpoint: endpoint
        )
    }

    func perform(
        _ action: BrowserMediaSessionAction,
        documentIdentifier: String
    ) {
        guard acceptsEvents,
            let webView,
            documentIdentifier.count
                <= BrowserMediaSessionPageEventDecoder.maximumDocumentIdentifierLength
        else { return }
        Task { @MainActor [weak webView] in
            _ = try? await webView?.callAsyncJavaScript(
                """
                return globalThis.__crestMediaSessionBridge?.perform(
                  action,
                  documentIdentifier
                ) === true;
                """,
                arguments: [
                    "action": action.rawValue,
                    "documentIdentifier": documentIdentifier,
                ],
                in: nil,
                contentWorld: BrowserMediaSessionContentBridge.contentWorld
            )
        }
    }

    /// Muting is an element property rather than a Media Session action, so it
    /// travels the same validated path as `perform` but addresses the elements
    /// the page has surfaced instead of a registered handler.
    func setMuted(
        _ muted: Bool,
        documentIdentifier: String
    ) {
        guard acceptsEvents,
            let webView,
            documentIdentifier.count
                <= BrowserMediaSessionPageEventDecoder.maximumDocumentIdentifierLength
        else { return }
        Task { @MainActor [weak webView] in
            _ = try? await webView?.callAsyncJavaScript(
                """
                return globalThis.__crestMediaSessionBridge?.setMuted(
                  muted,
                  documentIdentifier
                ) === true;
                """,
                arguments: [
                    "muted": muted,
                    "documentIdentifier": documentIdentifier,
                ],
                in: nil,
                contentWorld: BrowserMediaSessionContentBridge.contentWorld
            )
        }
    }

    private func invalidate() {
        guard let endpoint else { return }
        store.invalidate(endpoint: endpoint)
    }
}
