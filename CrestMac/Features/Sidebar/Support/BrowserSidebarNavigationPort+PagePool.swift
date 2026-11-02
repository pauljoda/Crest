import Foundation

extension BrowserSidebarNavigationPort {
    /// Binds the sidebar's navigation strip to the window's card pool.
    ///
    /// The pool and the store are captured rather than read once: every closure
    /// goes back to them at call time, which is what keeps the strip's disabled
    /// states and its reload glyph inside Observation's tracking. Reload is the
    /// one thing the pool cannot answer alone — it reloads *the session's*
    /// selected page — so the store rides along for that.
    init(pages: BrowserPagePool, browser: BrowserStore, showHistory: @escaping () -> Void) {
        self.init(
            canGoBack: { pages.canGoBack },
            canGoForward: { pages.canGoForward },
            backHistory: { pages.backHistory },
            forwardHistory: { pages.forwardHistory },
            goBack: { pages.goBack() },
            goForward: { pages.goForward() },
            goBackToHistoryItem: { item in pages.goBack(to: item) },
            goForwardToHistoryItem: { item in pages.goForward(to: item) },
            showHistory: showHistory,
            isLoading: { pages.activePage?.live.isLoading == true },
            hasActivePage: { pages.activePage != nil },
            activeURL: { pages.activePage?.live.displayURL },
            reloadOrStop: { pages.reloadOrStop() },
            reload: { pages.forceReload() },
            reloadFromOrigin: { pages.reloadFromOrigin() },
            clearCookiesAndReload: { await pages.activePage?.clearSiteData(.siteData) }
        )
    }

    /// Binds the strip to one page that the window is not showing, such as an
    /// unfocused Split View card's. Every action, History included, brings the
    /// card forward with `focus` before it acts.
    init(page: BrowserPage?, showHistory: @escaping () -> Void, focus: @escaping () -> Void) {
        self.init(
            canGoBack: { page?.live.canGoBack == true },
            canGoForward: { page?.live.canGoForward == true },
            backHistory: { page?.backHistory ?? [] },
            forwardHistory: { page?.forwardHistory ?? [] },
            goBack: {
                focus()
                page?.goBack()
            },
            goForward: {
                focus()
                page?.goForward()
            },
            goBackToHistoryItem: { item in
                focus()
                page?.goToHistory(item)
            },
            goForwardToHistoryItem: { item in
                focus()
                page?.goToHistory(item)
            },
            showHistory: {
                focus()
                showHistory()
            },
            isLoading: { page?.live.isLoading == true },
            hasActivePage: { page != nil },
            activeURL: { page?.live.displayURL },
            reloadOrStop: {
                focus()
                page?.performReload(.standard)
            },
            reload: {
                focus()
                page?.reload()
            },
            reloadFromOrigin: {
                focus()
                page?.performReload(.fromOrigin)
            },
            clearCookiesAndReload: {
                focus()
                await page?.clearSiteData(.siteData)
            }
        )
    }
}
