import Foundation
import Observation

protocol BrowserExtensionRegistryPersisting: AnyObject {
    func load() -> [BrowserExtensionInstallation]
    func save(_ installations: [BrowserExtensionInstallation])
}
