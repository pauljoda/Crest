/// Where the Split View focus preference is read and written.
protocol BrowserSplitFocusPreferencePersisting {
    func load() -> BrowserSplitFocusPreference
    func saveFollowsMouse(_ followsMouse: Bool)
}
