import Foundation
import WebKit

extension BrowserPlatformPage {
    var webKitView: WKWebView? { webView }
    /// The WebKit port behind this page, or nil when another engine hosts it.
    var webKitEngine: BrowserWebKitPageEngine? { (pageEngine as any BrowserPageEngine) as? BrowserWebKitPageEngine }

    func goBack() {
        refreshNavigationState()
        if navigationFailure != nil {
            returnFromNavigationFailure()
            return
        }
        pageEngine.navigateHistory(by: -1)
    }

    func goForward() {
        refreshNavigationState()
        pageEngine.navigateHistory(by: 1)
    }

    var backHistory: [BrowserNavigationHistoryItem] { pageEngine.backHistory }
    var forwardHistory: [BrowserNavigationHistoryItem] { pageEngine.forwardHistory }

    func goBack(toDepth depth: Int) {
        guard depth > 0, backHistory.contains(where: { $0.depth == depth }) else { return }
        clearNavigationFailure()
        pageEngine.navigateHistory(by: -depth)
    }

    func goForward(toDepth depth: Int) {
        guard depth > 0, forwardHistory.contains(where: { $0.depth == depth }) else { return }
        clearNavigationFailure()
        pageEngine.navigateHistory(by: depth)
    }

    /// Intercepted, same-document navigations have no didFinish callback.
    /// Retire their pending destination once WebKit publishes that URL, and
    /// publish history from the same observation path as the address bar.
    func synchronizeNavigationHistory() {
        // A page without a WebKit view has no back-forward list to read; the
        // Chromium port publishes its own history through the engine port.
        guard let webView = webKitView else { return }
        if let pendingNavigationURL, webView.url == pendingNavigationURL,
            webView.backForwardList.currentItem?.url == pendingNavigationURL
        {
            self.pendingNavigationURL = nil
        }
        navigationHistory.synchronize(with: webView.backForwardList)
    }

    func reload() { pageEngine.reload(bypassingCache: false) }

    func clearSiteDataAndReload() async {
        guard let webView = webKitView else {
            // An engine with its own website data clears it itself.
            if await pageEngine.clearSiteData() { pageEngine.reload(bypassingCache: true) }
            return
        }
        guard let targetURL = displayURL ?? webView.url else { return }
        await BrowserWebsiteDataStore.clearSiteData(
            for: targetURL,
            in: webView.configuration.websiteDataStore
        )
        if webView.url == nil {
            load(targetURL)
        } else {
            webView.reloadFromOrigin()
        }
    }

    func performReload(_ mode: BrowserPageReloadMode) {
        switch BrowserPageReloadPolicy.action(isLoading: isLoading, mode: mode) {
        case .stop: pageEngine.stop()
        case .reload: pageEngine.reload(bypassingCache: false)
        case .reloadFromOrigin: pageEngine.reload(bypassingCache: true)
        }
    }

    func stopLoading() { pageEngine.stop() }

    func retryAfterNavigationFailure() {
        guard
            let url = navigationFailure?.failingURL
                ?? pendingNavigationURL
                ?? self.url
        else { return }
        load(url)
    }

    var canProceedAfterCertificateFailure: Bool {
        navigationFailure?.kind == .secureConnectionFailed
            && pendingServerTrustIdentity != nil
    }

    func proceedAfterCertificateFailure() {
        guard canProceedAfterCertificateFailure,
            let identity = pendingServerTrustIdentity
        else { return }
        serverTrustOverrides.approve(identity, for: profileID)
        retryAfterNavigationFailure()
    }

    func returnFromNavigationFailure() {
        guard let webView = webKitView, let navigationFailure else { return }
        let shouldNavigateBack =
            navigationFailure.phase == .committed
            && webView.canGoBack
        clearNavigationFailure()
        if shouldNavigateBack {
            webView.goBack()
        }
    }

    var canReturnFromNavigationFailure: Bool {
        guard let webView = webKitView, let navigationFailure else { return false }
        if navigationFailure.phase == .provisional, webView.url != nil {
            return true
        }
        return webView.canGoBack
    }

    /// True when Crest, not web content, asked for this navigation. Two signals
    /// answer that: the exact URL Crest last passed to `load(_:)`, which web
    /// content never reaches, and a source frame that is not a web document —
    /// WebKit reports an empty origin for a load the app started against a web
    /// view with no page yet, and a `file:` origin for a local document's own
    /// links. Only such a navigation may reach a `file:` URL.
    func isAppInitiated(_ navigationAction: WKNavigationAction) -> Bool {
        if let appInitiatedURL, navigationAction.request.url == appInitiatedURL {
            return true
        }
        if let sourceOriginProvider = navigationAction as? any BrowserNavigationActionSourceOriginProviding {
            guard let origin = sourceOriginProvider.browserSourceOrigin else {
                return false
            }
            if origin.scheme.isEmpty, origin.host.isEmpty {
                return true
            }
            return origin.scheme == "file"
        }
        let origin = navigationAction.sourceFrame.securityOrigin
        let scheme = origin.protocol.lowercased()
        if scheme.isEmpty, origin.host.isEmpty {
            return true
        }
        return scheme == "file"
    }

    /// Forgets the URL Crest asked this page to load, once WebKit has begun the
    /// navigation that honored it.
    ///
    /// The marker is a one-shot authorization. Leaving it in place would let web
    /// content replay the exact URL Crest once loaded — the one way past the gate
    /// that keeps `file:` destinations app-initiated.
    func consumeAppInitiatedURL() {
        appInitiatedURL = nil
    }

    func isCurrentNavigation(_ navigation: WKNavigation?) -> Bool {
        // WebKit can deliver a callback late, after its navigation finished or
        // was replaced. An identified navigation is only current while it is
        // still the active one, so a stale failure cannot paint an error over a
        // page that already loaded. Callbacks that identify no navigation stay
        // accepted because WebKit reports unattributed loads that way.
        guard let navigation else { return true }
        return activeNavigation === navigation
    }
}
