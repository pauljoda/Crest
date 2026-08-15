protocol BrowserExtensionUpdatePreferencesPersisting: AnyObject {
    func load() -> BrowserExtensionUpdatePreferences?
    func save(_ preferences: BrowserExtensionUpdatePreferences)
}
