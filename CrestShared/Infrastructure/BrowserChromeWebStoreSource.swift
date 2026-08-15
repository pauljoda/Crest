import Foundation
import Observation

struct BrowserChromeWebStoreSource: Codable, Equatable, Sendable {
    let extensionID: BrowserChromeExtensionID
    let storeURL: URL
    let crxSHA256Hex: String
    let publisherKeyHashHex: String
}
