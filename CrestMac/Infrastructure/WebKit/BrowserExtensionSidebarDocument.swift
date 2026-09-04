import AppKit
import Observation
import WebKit

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
    @ObservationIgnored private var hasRecoveredProcess = false

    init(url: URL, tabID: TabID?, configuration: BrowserExtensionPageConfiguration, openTab: @escaping (URL) -> Void) {
        self.url = url
        self.tabID = tabID
        extensionBaseURL = configuration.baseURL
        self.openTab = openTab
        let webView = WKWebView(frame: .zero, configuration: configuration.webViewConfiguration)
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true
        webView.underPageBackgroundColor = .clear
        webView.appearance = NSApp.effectiveAppearance
        webView.load(URLRequest(url: url))
    }

    func close() {
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
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
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
        case .allow: decisionHandler(.allow)
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) { errorDescription = nil }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error
    ) {
        if (error as NSError).code != NSURLErrorCancelled { errorDescription = error.localizedDescription }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
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
