import Foundation

/// The engine build an adapter wraps. The raw values are the descriptor's
/// `implementationId` and the token namespace staged navigations carry.
enum BrowserEngineImplementation: String, Codable, Sendable {
    case webKitMacOS = "crest.webkit.macos"
    case webKitIOS = "crest.webkit.ios"
    case chromiumMacOS = "crest.chromium.macos"

    // MARK: - Types

    enum Family: Sendable {
        case webKit
        case chromium
    }

    // MARK: - Variables

    var family: Family {
        switch self {
        case .webKitMacOS, .webKitIOS: .webKit
        case .chromiumMacOS: .chromium
        }
    }

    /// The platform name used in the descriptor's human-readable scope.
    var platformName: String {
        switch self {
        case .webKitMacOS, .chromiumMacOS: "macOS"
        case .webKitIOS: "iOS"
        }
    }
}
