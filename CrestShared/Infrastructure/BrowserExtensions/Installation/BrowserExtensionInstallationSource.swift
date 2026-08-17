import Foundation
import Observation

enum BrowserExtensionInstallationSource: Codable, Equatable, Sendable {
    case unpackedPackage
    case safariWebExtension(BrowserSafariWebExtensionSource)
    case chromeWebStore(BrowserChromeWebStoreSource)
    case mozillaAddons(BrowserMozillaAddonsSource)
}
