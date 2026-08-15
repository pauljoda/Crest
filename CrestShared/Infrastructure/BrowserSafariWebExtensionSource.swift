import Foundation
import Observation

struct BrowserSafariWebExtensionSource: Codable, Equatable, Sendable {
    let applicationBookmark: Data
    let applicationBundleIdentifier: String
    let extensionBundleIdentifier: String
    let relativeBundlePath: String
    let developerTeamIdentifier: String?
}
