import Foundation

extension BrowserSidebarNavigationPort {
    /// Binds the navigation controls to the one page `page` answers at call
    /// time, as a Quick Window shows: it trades its page for another when it
    /// changes Space, so the page is read, never captured. Every navigation
    /// first runs `recordActivity`.
    init(
        page: @escaping () -> BrowserPage?, recordActivity: @escaping () -> Void = {},
        showHistory: @escaping () -> Void
    ) {
        self.init(
            canGoBack: { page()?.live.canGoBack == true },
            canGoForward: { page()?.live.canGoForward == true },
            backHistory: { page()?.backHistory ?? [] },
            forwardHistory: { page()?.forwardHistory ?? [] },
            goBack: {
                recordActivity()
                page()?.goBack()
            },
            goForward: {
                recordActivity()
                page()?.goForward()
            },
            goBackToHistoryItem: { item in
                recordActivity()
                page()?.goToHistory(item)
            },
            goForwardToHistoryItem: { item in
                recordActivity()
                page()?.goToHistory(item)
            },
            showHistory: showHistory,
            isLoading: { page()?.live.isLoading == true },
            hasActivePage: { page() != nil },
            activeURL: { page()?.live.displayURL },
            reloadOrStop: {
                recordActivity()
                page()?.performReload(.standard)
            },
            reload: {
                recordActivity()
                page()?.performReload(.standard)
            },
            reloadFromOrigin: {
                recordActivity()
                page()?.performReload(.fromOrigin)
            },
            clearCookiesAndReload: { await page()?.clearSiteData(.siteData) }
        )
    }
}
