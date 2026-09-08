import Foundation

struct BrowserVerifiedCRX3Package: Equatable, Sendable {
    let extensionID: BrowserChromeExtensionID
    let crxData: Data
    let zipArchiveData: Data
    let crxSHA256Hex: String
    let publisherKeyHashHex: String
}
