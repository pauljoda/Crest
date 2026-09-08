import Foundation
import Observation

final class InMemoryBrowserExtensionRegistryPersistence:
    BrowserExtensionRegistryPersisting
{
    private(set) var installations: [BrowserExtensionInstallation]

    init(installations: [BrowserExtensionInstallation] = []) {
        self.installations = installations
    }

    func load() -> [BrowserExtensionInstallation] {
        installations
    }

    func save(_ installations: [BrowserExtensionInstallation]) {
        self.installations = installations
    }
}
