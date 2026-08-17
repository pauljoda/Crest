import Foundation
import Observation

enum BrowserExtensionInstallationSource: Codable, Equatable, Sendable {
    case unpackedPackage
    case localPackage(BrowserLocalExtensionSource)
    case safariWebExtension(BrowserSafariWebExtensionSource)
    case chromeWebStore(BrowserChromeWebStoreSource)
    case mozillaAddons(BrowserMozillaAddonsSource)
}
