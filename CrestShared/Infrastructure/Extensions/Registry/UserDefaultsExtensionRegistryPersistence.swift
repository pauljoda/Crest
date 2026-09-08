import Foundation
import Observation

final class UserDefaultsBrowserExtensionRegistryPersistence:
    BrowserExtensionRegistryPersisting
{
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "crest.extensions.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [BrowserExtensionInstallation] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return
            (try? JSONDecoder().decode(
                [BrowserExtensionInstallation].self,
                from: data
            )) ?? []
    }

    func save(_ installations: [BrowserExtensionInstallation]) {
        guard let data = try? JSONEncoder().encode(installations) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
