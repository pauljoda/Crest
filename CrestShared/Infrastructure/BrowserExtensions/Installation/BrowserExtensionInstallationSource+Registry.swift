import Foundation
import Observation

extension BrowserExtensionInstallationSource {
    var isChromeWebStore: Bool {
        if case .chromeWebStore = self { return true }
        return false
    }
}
