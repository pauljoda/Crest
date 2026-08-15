final class InMemoryBrowserLinkPreferencesPersistence:
    BrowserLinkPreferencesPersisting
{
    private var preferences: BrowserLinkPreferences?

    init(preferences: BrowserLinkPreferences? = nil) {
        self.preferences = preferences
    }

    func load() -> BrowserLinkPreferences? {
        preferences
    }

    func save(_ preferences: BrowserLinkPreferences) {
        self.preferences = preferences
    }

    func remove() {
        preferences = nil
    }
}
