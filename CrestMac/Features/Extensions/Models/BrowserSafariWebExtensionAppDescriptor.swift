import Foundation

struct BrowserSafariWebExtensionAppDescriptor: Equatable, Identifiable, Sendable {
    let applicationURL: URL
    let applicationDisplayName: String
    let applicationBundleIdentifier: String
    let extensionBundleURL: URL
    let extensionBundleIdentifier: String
    let displayName: String
    let version: String?
    let relativeBundlePath: String

    var id: String { extensionBundleIdentifier }
}
