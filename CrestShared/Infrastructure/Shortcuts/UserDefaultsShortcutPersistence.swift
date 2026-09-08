import Foundation

struct UserDefaultsBrowserShortcutPersistence: BrowserShortcutPersisting {
    static let currentKey = "crest.keyboard-shortcuts.v1"

    private let defaults: UserDefaults
    private let persistenceKey: String

    init(
        defaults: UserDefaults,
        persistenceKey: String = currentKey
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
    }

    func load() -> [String: BrowserShortcutOverride]? {
        guard let data = defaults.data(forKey: persistenceKey),
            let records = try? JSONDecoder().decode(
                [String: BrowserShortcutPersistenceRecord].self,
                from: data
            )
        else {
            return nil
        }
        return records.mapValues(\.shortcutOverride)
    }

    func save(_ overrides: [String: BrowserShortcutOverride]) {
        let records = overrides.mapValues(
            BrowserShortcutPersistenceRecord.init
        )
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: persistenceKey)
    }

    func remove() {
        defaults.removeObject(forKey: persistenceKey)
    }
}
