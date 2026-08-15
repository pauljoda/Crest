enum BrowserPinnedTabInteraction {
    static func shouldRestoreSavedLocation(for tab: BrowserTab) -> Bool {
        tab.placement == .pinned && tab.isAwayFromSavedLocation
    }
}
