import Foundation

extension BrowserPlatformPage {
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
    /// Retire their pending destination once the engine publishes that URL, and
    /// publish history from the same observation path as the address bar.
    func synchronizeNavigationHistory() {
        let currentEntryURL = pageEngine.synchronizeHistory()
        if let pendingNavigationURL, pageEngine.currentURL == pendingNavigationURL,
            currentEntryURL == pendingNavigationURL
        {
            self.pendingNavigationURL = nil
        }
    }

    func reload() { pageEngine.reload(bypassingCache: false) }

    func clearSiteDataAndReload() async {
        guard let targetURL = displayURL ?? pageEngine.currentURL,
            await pageEngine.clearSiteData(for: targetURL)
        else { return }
        if pageEngine.currentURL == nil {
            load(targetURL)
        } else {
            pageEngine.reload(bypassingCache: true)
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

    /// Leaves the failure notice for the page behind it. A committed failure
    /// replaced that page, so it goes back; an engine that reports its own
    /// state shows its error as a committed document too.
    func returnFromNavigationFailure() {
        guard let navigationFailure else { return }
        let replacedPage = navigationFailure.phase == .committed || pageEngine.reportsNavigationState
        let shouldNavigateBack = replacedPage && pageEngine.canGoBack
        clearNavigationFailure()
        if shouldNavigateBack {
            pageEngine.navigateHistory(by: -1)
        }
    }

    var canReturnFromNavigationFailure: Bool {
        guard let navigationFailure else { return false }
        if navigationFailure.phase == .provisional, !pageEngine.reportsNavigationState,
            pageEngine.currentURL != nil
        {
            return true
        }
        return pageEngine.canGoBack
    }

    /// Forgets the URL Crest asked this page to load, once the engine has begun
    /// the navigation that honored it.
    ///
    /// The marker is a one-shot authorization. Leaving it in place would let web
    /// content replay the exact URL Crest once loaded — the one way past the gate
    /// that keeps `file:` destinations app-initiated.
    func consumeAppInitiatedURL() {
        appInitiatedURL = nil
    }
}
