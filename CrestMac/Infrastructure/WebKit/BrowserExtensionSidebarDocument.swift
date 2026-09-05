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
    /// Absent when the pool has no cookie-access service behind it.
    @ObservationIgnored private let cookieAccess: BrowserExtensionFramedSiteCookieAccess?
    @ObservationIgnored private var hasRecoveredProcess = false
    /// The page-world `chrome.runtime` alias and relay on this document's
    /// private content controller.
    @ObservationIgnored private var runtimeBridge: BrowserExtensionHostedDocumentRuntimeBridge.Handle?
    @ObservationIgnored private let contentController = WKUserContentController()

    init(
        url: URL,
        tabID: TabID?,
        configuration: BrowserExtensionPageConfiguration,
        cookieAccess: BrowserExtensionFramedSiteCookieAccess?,
        installRuntimeBridge: (WKUserContentController) -> BrowserExtensionHostedDocumentRuntimeBridge.Handle? = { _ in
            nil
        },
        openTab: @escaping (URL) -> Void
    ) {
        self.url = url
        self.tabID = tabID
        extensionBaseURL = configuration.baseURL
        self.cookieAccess = cookieAccess
        self.openTab = openTab
        guard BrowserExtensionHostedContentIsolationPolicy.isSupported else {
            super.init()
            errorDescription = String(localized: "This version of WebKit cannot isolate extension side panels.")
            return
        }
        runtimeBridge = installRuntimeBridge(contentController)
        let webView = WKWebView(frame: .zero, configuration: configuration.webViewConfiguration)
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true
        webView.underPageBackgroundColor = .clear
        webView.appearance = NSApp.effectiveAppearance
        browserExtensionSidebarDocumentLog.info("panel document load \(url.absoluteString, privacy: .public)")
        webView.load(URLRequest(url: url))
    }

    func close() {
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
        if action.targetFrame?.isMainFrame == false {
            browserExtensionSidebarDocumentLog.info(
                "panel frame navigation \(url.host() ?? "-", privacy: .public)\(url.path(), privacy: .public) decision=\(String(describing: decision), privacy: .public)"
            )
        }
        switch decision {
        case .allow:
            // A framed site's cookies have to be usable before the frame's own
            // request goes out, so the decision waits on the rewrite. Every
            // other navigation is answered without a hop.
            guard let cookieAccess, let host = cookieAccess.hostRequiringRewrite(for: action) else {
                decisionHandler(.allow)
                return
            }
            Task { @MainActor in
                await cookieAccess.relaxCookies(for: host)
                decisionHandler(.allow)
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
        browserExtensionSidebarDocumentLog.info(
            "panel document finished \(webView.url?.absoluteString ?? "<nil>", privacy: .public)")
        errorDescription = nil
    }

    /// Subframe loads never reach the main-frame delegate callbacks, so their
    /// responses are the only signal of what a framed site answered.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse {
            let url = http.url
            browserExtensionSidebarDocumentLog.info(
                "panel frame response \(http.statusCode, privacy: .public) \(url?.host() ?? "-", privacy: .public)\(url?.path() ?? "", privacy: .public) \(http.mimeType ?? "-", privacy: .public) location=\(http.value(forHTTPHeaderField: "Location") ?? "-", privacy: .public)"
            )
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error
    ) {
        browserExtensionSidebarDocumentLog.error(
            "panel document provisional failure \(String(describing: error), privacy: .public)")
        if (error as NSError).code != NSURLErrorCancelled { errorDescription = error.localizedDescription }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        browserExtensionSidebarDocumentLog.error(
            "panel document failure \(String(describing: error), privacy: .public)")
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
