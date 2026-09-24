import Foundation

extension BrowserPlatformPage {
    func goBack() {
        refreshNavigationState()
        if live.failure != nil {
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
        corePage.leaveFailure()
        pageEngine.navigateHistory(by: -depth)
    }

    func goForward(toDepth depth: Int) {
        guard depth > 0, forwardHistory.contains(where: { $0.depth == depth }) else { return }
        corePage.leaveFailure()
        pageEngine.navigateHistory(by: depth)
    }

    /// Intercepted, same-document navigations have no didFinish callback.
    /// Retire their pending destination once the engine publishes that URL, and
    /// publish history from the same observation path as the address bar.
    func synchronizeNavigationHistory() {
        let currentEntryURL = pageEngine.synchronizeHistory()
        if pageEngine.currentURL == currentEntryURL { navigationReporter?.arrived(at: currentEntryURL) }
    }

    func reload() { pageEngine.reload(bypassingCache: false) }

    func clearSiteDataAndReload() async {
        guard let targetURL = live.displayURL ?? pageEngine.currentURL,
            await pageEngine.clearSiteData(for: targetURL)
        else { return }
        if pageEngine.currentURL == nil {
            corePage.navigate(to: targetURL.absoluteString)
        } else {
            pageEngine.reload(bypassingCache: true)
        }
    }

    func performReload(_ mode: BrowserPageReloadMode) {
        switch BrowserPageReloadPolicy.action(isLoading: live.isLoading, mode: mode) {
        case .stop: pageEngine.stop()
        case .reload: pageEngine.reload(bypassingCache: false)
        case .reloadFromOrigin: pageEngine.reload(bypassingCache: true)
        }
    }

    func stopLoading() { pageEngine.stop() }

    func retryAfterNavigationFailure() {
        guard let url = live.displayURL else { return }
        corePage.navigate(to: url.absoluteString)
    }

    var canProceedAfterCertificateFailure: Bool {
        live.failure?.error == .secureConnectionFailed
            && pendingServerTrustIdentity != nil
    }

    func proceedAfterCertificateFailure() {
        guard canProceedAfterCertificateFailure,
            let identity = pendingServerTrustIdentity
        else { return }
        serverTrustOverrides.approve(identity, for: profileID)
        retryAfterNavigationFailure()
    }

    /// Leaves the failure notice for the page behind it. A failure that
    /// replaced that page, as a committed error page does, goes back to it.
    func returnFromNavigationFailure() {
        guard let failure = live.failure else { return }
        let shouldNavigateBack = failure.replacedDocument && pageEngine.canGoBack
        corePage.leaveFailure()
        if shouldNavigateBack {
            pageEngine.navigateHistory(by: -1)
        }
    }

    var canReturnFromNavigationFailure: Bool {
        guard let failure = live.failure else { return false }
        if !failure.replacedDocument, pageEngine.currentURL != nil { return true }
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
