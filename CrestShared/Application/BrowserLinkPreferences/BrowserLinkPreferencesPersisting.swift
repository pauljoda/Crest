protocol BrowserLinkPreferencesPersisting: AnyObject {
    func load() -> BrowserLinkPreferences?
    func save(_ preferences: BrowserLinkPreferences)
    func remove()
}
