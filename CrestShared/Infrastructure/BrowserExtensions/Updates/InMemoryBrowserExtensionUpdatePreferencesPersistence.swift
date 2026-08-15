final class InMemoryBrowserExtensionUpdatePreferencesPersistence:
    BrowserExtensionUpdatePreferencesPersisting
{
    private var preferences: BrowserExtensionUpdatePreferences?

    init(preferences: BrowserExtensionUpdatePreferences? = nil) {
        self.preferences = preferences
    }

    func load() -> BrowserExtensionUpdatePreferences? {
        preferences
    }

    func save(_ preferences: BrowserExtensionUpdatePreferences) {
        self.preferences = preferences
    }
}
