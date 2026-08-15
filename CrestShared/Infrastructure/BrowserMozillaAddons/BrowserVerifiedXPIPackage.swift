import Foundation

/// An add-on archive that matched the digest, size, and identity its
/// addons.mozilla.org listing published, and that carries Mozilla's signing
/// artifacts.
struct BrowserVerifiedXPIPackage: Equatable, Sendable {
    let extensionID: BrowserMozillaExtensionID
    let archiveData: Data
    let xpiSHA256Hex: String
}
