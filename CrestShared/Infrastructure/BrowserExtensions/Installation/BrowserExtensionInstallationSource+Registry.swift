import Foundation
import Observation

extension BrowserExtensionInstallationSource {
    var isChromeWebStore: Bool {
        if case .chromeWebStore = self { return true }
        return false
    }

    var isLocalPackage: Bool {
        if case .localPackage = self { return true }
        return false
    }
}
