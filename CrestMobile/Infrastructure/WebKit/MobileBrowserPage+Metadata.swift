extension MobileBrowserPage {
    var metadata: BrowserPageMetadata {
        BrowserPageMetadata(
            url: url, displayURL: displayURL, title: title,
            displayTitle: navigationFailure?.displayHost ?? title,
            faviconData: faviconData, iconAccent: siteThemeIconAccent
        )
    }
}
