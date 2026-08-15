enum BrowserTabActivationPolicy {
    static func activate(
        _ tabID: TabID,
        selectTab: (TabID) -> Void,
        presentPage: () -> Void
    ) {
        selectTab(tabID)
        presentPage()
    }
}
