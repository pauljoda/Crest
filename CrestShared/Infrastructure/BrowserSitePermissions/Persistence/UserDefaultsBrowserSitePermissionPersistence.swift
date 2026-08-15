import Foundation

final class UserDefaultsBrowserSitePermissionPersistence: BrowserSitePermissionPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "crest.site-permissions.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [BrowserSitePermissionRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BrowserSitePermissionRecord].self, from: data)) ?? []
    }

    func save(_ records: [BrowserSitePermissionRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
