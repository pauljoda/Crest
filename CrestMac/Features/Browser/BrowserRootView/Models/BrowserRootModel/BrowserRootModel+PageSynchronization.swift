extension BrowserRootModel {
    func synchronizePageMetadata() {
        guard let page = pages.activePage else { return }
        browser.updateSelectedTabFromPage(
            url: page.displayURL,
            title: page.navigationFailure?.displayHost ?? page.title,
            faviconData: page.faviconData,
            iconAccent: page.siteThemeIconAccent
        )
        if !isAddressEditing {
            address = (page.displayURL ?? browser.selectedTab?.url)?.absoluteString
                ?? ""
        }
    }

    func recordCompletedNavigation() {
        guard let page = pages.activePage, let url = page.url else { return }
        synchronizePageMetadata()
        browser.recordVisit(url: url, title: page.title)
        guard let space = browser.selectedSpace else { return }
        Task { await pages.styleVisitedLinks(in: space) }
    }
}
