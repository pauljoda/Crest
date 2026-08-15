import Foundation

final class UserDefaultsBrowserLinkPreferencesPersistence:
    BrowserLinkPreferencesPersisting
{
    static let currentKey = "crest.link-preferences.v1"

    private let defaults: UserDefaults
    private let persistenceKey: String

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = currentKey
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
    }

    func load() -> BrowserLinkPreferences? {
        guard let data = defaults.data(forKey: persistenceKey) else { return nil }
        return try? JSONDecoder().decode(BrowserLinkPreferences.self, from: data)
    }

    func save(_ preferences: BrowserLinkPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: persistenceKey)
    }

    func remove() {
        defaults.removeObject(forKey: persistenceKey)
    }
}
