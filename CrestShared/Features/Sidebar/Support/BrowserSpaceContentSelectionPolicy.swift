enum BrowserSpaceContentSelectionPolicy {
    // Keep sidebar paging animation independent from the resident WebKit host.
    // Waiting for the pager to settle leaves the selected tab and active page
    // out of sync long enough for the unloaded-tab fallback to render.
    static let defersWebContentUntilPagerSettles = false
    static let rootObserverDefersSpaceChanges = false
}
