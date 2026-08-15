import Foundation
import Observation

struct BrowserMozillaAddonsSource: Codable, Equatable, Sendable {
    let slug: BrowserMozillaAddonSlug
    let extensionID: BrowserMozillaExtensionID
    let storeURL: URL
    let version: String
    let xpiSHA256Hex: String
}
