import AppKit
import Observation
import WebKit
import os

private let browserExtensionSidebarDocumentLog = Logger(
    subsystem: ProductIdentity.serviceNamespace,
    category: "extension-sidebar"
)

struct BrowserExtensionSidebarKey: Hashable {
    let windowID: BrowserWindowID
    let spaceID: SpaceID
    let extensionBaseURL: URL
    let tabID: TabID?
}

/// A panel's configuration keeps its required extension origin for WebKit's
/// resource authorization. Exclude the view from WebKit's separate enumeration
/// of candidates for a background's related view: that relationship requires
/// the background's data store, whereas each panel has its own isolated store.
private final class BrowserExtensionPanelWebView: WKWebView {
    @objc(_requiredWebExtensionBaseURL)
    private func relatedExtensionBaseURL() -> NSURL? { nil }
}

/// An extension document, deliberately never registered as a browser tab.
@Observable
@MainActor
final class BrowserExtensionSidebarDocument: NSObject, WKNavigationDelegate, WKUIDelegate {
    let url: URL
    let tabID: TabID?
    let extensionBaseURL: URL
    /// This document's `runtime.getContexts` identity. Minted with the
    /// document and gone when it closes, which is the lifetime Chrome gives a
    /// context ID: a reopened panel is a new context, not the old one.
    let contextID = UUID().uuidString
    private(set) var webView: WKWebView?
    private(set) var errorDescription: String?
    @ObservationIgnored private let openTab: (URL) -> Void
    @ObservationIgnored private var hasRecoveredProcess = false
    /// The page-world `chrome.runtime` alias and relay on this document's
    /// private content controller.
    @ObservationIgnored private var runtimeBridge: BrowserExtensionHostedDocumentRuntimeBridge.Handle?
    @ObservationIgnored private let contentController = WKUserContentController()
    @ObservationIgnored private var session: BrowserExtensionPanelSession?
    @ObservationIgnored private var startup: Task<Void, Never>?

    init(
        url: URL,
        tabID: TabID?,
        configuration: BrowserExtensionPageConfiguration,
        installRuntimeBridge: (WKUserContentController) -> BrowserExtensionHostedDocumentRuntimeBridge.Handle? = { _ in
            nil
        },
        openTab: @escaping (URL) -> Void
    ) {
        self.url = url
        self.tabID = tabID
        extensionBaseURL = configuration.baseURL
        self.openTab = openTab
        guard BrowserExtensionHostedContentIsolationPolicy.isSupported,
            WKWebView.instancesRespond(to: NSSelectorFromString("_requiredWebExtensionBaseURL"))
        else {
            super.init()
            errorDescription = String(localized: "This version of WebKit cannot isolate extension side panels.")
            return
        }
        runtimeBridge = installRuntimeBridge(contentController)
        session = BrowserExtensionPanelSession(configuration: configuration, content: contentController)
        guard session != nil else {
            super.init()
            errorDescription = String(localized: "This version of WebKit cannot isolate extension side panels.")
            return
        }
        let webView = BrowserExtensionPanelWebView(frame: .zero, configuration: configuration.webViewConfiguration)
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true
        webView.underPageBackgroundColor = .clear
        webView.appearance = NSApp.effectiveAppearance
        session?.invalidate = { [weak self] in self?.close() }
        startup = Task { @MainActor [weak self] in
            guard let self else { return }
            let ready = await session?.prepare() == true
            guard !Task.isCancelled, self.webView === webView else { return }
            guard ready else {
                errorDescription = String(
                    localized: "The extension side panel stopped responding. Close and reopen it to try again.")
                return
            }
            webView.load(URLRequest(url: url))
        }
    }

    func close() {
        startup?.cancel()
        startup = nil
        session?.stop()
        session = nil
        runtimeBridge?.release()
        runtimeBridge = nil
        guard let webView else { return }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        (webView.superview as? BrowserWebHostView)?.detach()
        webView.removeFromSuperview()
        self.webView = nil
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        guard BrowserExtensionHostedContentIsolationPolicy.apply(contentController, to: preferences) else {
            decisionHandler(.cancel, preferences)
            return
        }
        self.webView(webView, decidePolicyFor: action) { policy in decisionHandler(policy, preferences) }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        let decision = BrowserExtensionSidebarNavigationPolicy.decide(
            url: url, extensionBaseURL: extensionBaseURL, isMainFrame: action.targetFrame?.isMainFrame ?? true,
            opensNewWindow: action.targetFrame == nil
        )
        switch decision {
        case .allow:
            Task { @MainActor [weak self] in
                let allowed = await self?.session?.allows(action) == true
                decisionHandler(allowed ? .allow : .cancel)
            }
        case .openTab:
            decisionHandler(.cancel)
            openTab(url)
        case .cancel: decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url,
            BrowserExtensionSidebarNavigationPolicy.decide(
                url: url, extensionBaseURL: extensionBaseURL, isMainFrame: true, opensNewWindow: true
            ) == .openTab
        {
            openTab(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        errorDescription = nil
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error
    ) {
        browserExtensionSidebarDocumentLog.error(
            "panel document provisional failure \(String(describing: error), privacy: .private)")
        if (error as NSError).code != NSURLErrorCancelled { errorDescription = error.localizedDescription }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        browserExtensionSidebarDocumentLog.error(
            "panel document failure \(String(describing: error), privacy: .private)")
        if (error as NSError).code != NSURLErrorCancelled { errorDescription = error.localizedDescription }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !hasRecoveredProcess else {
            errorDescription = String(
                localized: "The extension side panel stopped responding. Close and reopen it to try again.")
            return
        }
        hasRecoveredProcess = true
        webView.reload()
    }
}
