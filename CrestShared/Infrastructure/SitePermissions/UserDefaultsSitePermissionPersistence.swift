import Foundation

/// The saved document lives where it always has, so existing choices load
/// without a migration.
final class UserDefaultsBrowserSitePermissionPersistence: BrowserSitePermissionPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "crest.site-permissions.v1") {
        self.defaults = defaults
        self.key = key
    }

    func loadDocument() -> Data? {
        defaults.data(forKey: key)
    }

    func saveDocument(_ document: Data) {
        defaults.set(document, forKey: key)
    }
}
