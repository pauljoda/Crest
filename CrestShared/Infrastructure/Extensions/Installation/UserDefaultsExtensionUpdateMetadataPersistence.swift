import Foundation

final class UserDefaultsBrowserExtensionUpdateMetadataPersistence:
    BrowserExtensionUpdateMetadataPersisting
{
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "crest.extensions.auto-update.last-checked-at.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func loadLastCheckedAt() -> Date? {
        defaults.object(forKey: key) as? Date
    }

    func saveLastCheckedAt(_ date: Date) {
        defaults.set(date, forKey: key)
    }
}
