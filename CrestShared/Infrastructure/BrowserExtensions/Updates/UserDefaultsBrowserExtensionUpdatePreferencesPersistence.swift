import Foundation

final class UserDefaultsBrowserExtensionUpdatePreferencesPersistence:
    BrowserExtensionUpdatePreferencesPersisting
{
    static let currentKey = "crest.extensions.auto-update.v1"

    private let defaults: UserDefaults
    private let persistenceKey: String

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = currentKey
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
    }

    func load() -> BrowserExtensionUpdatePreferences? {
        guard let data = defaults.data(forKey: persistenceKey) else {
            return nil
        }
        return try? JSONDecoder().decode(
            BrowserExtensionUpdatePreferences.self,
            from: data
        )
    }

    func save(_ preferences: BrowserExtensionUpdatePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: persistenceKey)
    }

    func reset() {
        defaults.removeObject(forKey: persistenceKey)
    }
}
