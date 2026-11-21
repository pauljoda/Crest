import Foundation

extension BrowserSidebarNavigationPort {
    /// Binds the sidebar's navigation strip to the compact shell's page
    /// actions.
    ///
    /// The compact shell's page port serves the whole compact chrome — the
    /// page menu, the share sheet, reader mode, zoom — and the strip is only
    /// one of its readers. This narrows it to the eleven questions the strip
    /// actually asks, so the shared strip never sees the rest.
    ///
    /// The actions are optional because the compact shell has no page at all
    /// between tabs. Absent, every question answers the way an empty strip
    /// needs it to.
    init(pageActions: MobileSelectedPageActionPort?, showHistory: @escaping () -> Void) {
        self.init(
            canGoBack: { pageActions?.canGoBack == true },
            canGoForward: { pageActions?.canGoForward == true },
            backHistory: { pageActions?.backHistory ?? [] },
            forwardHistory: { pageActions?.forwardHistory ?? [] },
            goBack: { pageActions?.goBack() },
            goForward: { pageActions?.goForward() },
            goBackToHistoryItem: { item in pageActions?.goBack(to: item) },
            goForwardToHistoryItem: { item in
                pageActions?.goForward(to: item)
            },
            showHistory: showHistory,
            isLoading: { pageActions?.activePage?.live.isLoading == true },
            hasActivePage: { pageActions?.isAvailable == true },
            activeURL: { pageActions?.activeURL },
            reloadOrStop: { pageActions?.reloadOrStop() },
            reload: { pageActions?.reload() },
            reloadFromOrigin: { pageActions?.reloadFromOrigin() },
            clearCookiesAndReload: {
                await pageActions?.clearSiteData(.siteData)
            }
        )
    }
}
