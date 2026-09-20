import Foundation
import WebKit

extension BrowserPlatformPage {
    func goBack() {
        #if CREST_CHROMIUM_HOST
        if let chromiumPage { chromiumPage.command("engine.back"); return }
        #endif
        refreshNavigationState()
        if navigationFailure != nil {
            returnFromNavigationFailure()
            return
        }
        if let item = navigationHistory.backItems.last {
            webView.go(to: item)
        } else {
            webView.goBack()
        }
    }

    func goForward() {
        #if CREST_CHROMIUM_HOST
        if let chromiumPage { chromiumPage.command("engine.forward"); return }
        #endif
        refreshNavigationState()
        if let item = navigationHistory.forwardItems.first {
            webView.go(to: item)
        } else {
            webView.goForward()
        }
    }

    var backHistory: [BrowserNavigationHistoryItem] {
        navigationHistory.backItems.reversed().enumerated().map { index, item in
            BrowserNavigationHistoryItem(
                depth: index + 1,
                title: Self.navigationTitle(for: item),
                url: item.url
            )
        }
    }

    var forwardHistory: [BrowserNavigationHistoryItem] {
        navigationHistory.forwardItems.enumerated().map { index, item in
            BrowserNavigationHistoryItem(
                depth: index + 1,
                title: Self.navigationTitle(for: item),
                url: item.url
            )
        }
    }

    func goBack(toDepth depth: Int) {
        refreshNavigationState()
        let items = navigationHistory.backItems
        let index = items.count - depth
        guard items.indices.contains(index) else { return }
        clearNavigationFailure()
        webView.go(to: items[index])
    }

    func goForward(toDepth depth: Int) {
        refreshNavigationState()
        let items = navigationHistory.forwardItems
        let index = depth - 1
        guard items.indices.contains(index) else { return }
        clearNavigationFailure()
        webView.go(to: items[index])
    }

    /// Intercepted, same-document navigations have no didFinish callback.
    /// Retire their pending destination once WebKit publishes that URL, and
    /// publish history from the same observation path as the address bar.
    func synchronizeNavigationHistory() {
        #if CREST_CHROMIUM_HOST
        if chromiumPage != nil { return }
        #endif
        if let pendingNavigationURL, webView.url == pendingNavigationURL,
            webView.backForwardList.currentItem?.url == pendingNavigationURL
        {
            self.pendingNavigationURL = nil
        }
        navigationHistory.synchronize(with: webView.backForwardList)
    }

    func reload() {
        #if CREST_CHROMIUM_HOST
        if let chromiumPage { chromiumPage.command("engine.reload"); return }
        #endif
        webView.reload()
    }

    func clearSiteDataAndReload() async {
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
        #if CREST_CHROMIUM_HOST
        if let chromiumPage {
            switch BrowserPageReloadPolicy.action(isLoading: isLoading, mode: mode) {
            case .stop: chromiumPage.command("engine.stop")
            case .reload, .reloadFromOrigin: chromiumPage.command("engine.reload")
            }
            return
        }
        #endif
        switch BrowserPageReloadPolicy.action(isLoading: isLoading, mode: mode) {
        case .stop:
            webView.stopLoading()
        case .reload:
            webView.reload()
        case .reloadFromOrigin:
            webView.reloadFromOrigin()
        }
    }

    func stopLoading() {
        #if CREST_CHROMIUM_HOST
        if let chromiumPage { chromiumPage.command("engine.stop"); return }
        #endif
        webView.stopLoading()
    }

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
        guard let navigationFailure else { return }
        let shouldNavigateBack =
            navigationFailure.phase == .committed
            && webView.canGoBack
        clearNavigationFailure()
        if shouldNavigateBack {
            webView.goBack()
        }
    }

    var canReturnFromNavigationFailure: Bool {
        guard let navigationFailure else { return false }
        if navigationFailure.phase == .provisional, webView.url != nil {
            return true
        }
        return webView.canGoBack
    }

    private static func navigationTitle(for item: WKBackForwardListItem) -> String {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        return item.url.host() ?? item.url.absoluteString
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
