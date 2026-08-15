extension MobileBrowserRootModel {
    func synchronizePageMetadata(isAddressEditing: Bool) {
        guard let page = selectedPage else { return }
        browser.updateSelectedTabFromPage(
            url: page.displayURL,
            title: page.navigationFailure?.displayHost ?? page.title,
            faviconData: page.faviconData,
            iconAccent: page.siteThemeIconAccent
        )
        if !isAddressEditing {
            address =
                (page.displayURL ?? browser.selectedTab?.url)?.absoluteString
                ?? ""
        }
    }

    func recordCompletedNavigation(isAddressEditing: Bool) {
        guard let page = selectedPage,
            let url = page.url
        else { return }
        synchronizePageMetadata(isAddressEditing: isAddressEditing)
        browser.recordVisit(url: url, title: page.title)
        guard let space = browser.selectedSpace else { return }
        Task { await pages.styleVisitedLinks(in: space) }
    }
}
