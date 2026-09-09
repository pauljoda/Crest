import Foundation

struct BrowserExtensionPackage: Equatable, Sendable {
    let extensionID: String
    let packageName: String
    let resourceURL: URL
}
