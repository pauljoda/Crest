import Foundation

/// Stable identity for one extension that consumes Crest's emulated
/// WebExtension services.
///
/// WebKit fixes the JavaScript surface `WKWebExtension` exposes, so namespaces
/// such as `chrome.notifications` and `chrome.history` are polyfilled into
/// extension background scripts and bridged to the app. The bridge derives one
/// client identity per installed extension, and every emulated service keys its
/// per-extension state on that identity. The raw value is deliberately opaque:
/// Chrome Web Store identifiers, unpacked development identifiers, and WebKit's
/// own unique identifiers all encode cleanly.
struct BrowserExtensionServiceClientID:
    Codable,
    Comparable,
    Equatable,
    Hashable,
    RawRepresentable,
    Sendable
{
    let rawValue: String

    init?(_ rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    init?(rawValue: String) {
        self.init(rawValue)
    }

    static func scoped(
        extensionID: String,
        spaceID: SpaceID
    ) -> BrowserExtensionServiceClientID {
        guard
            let clientID = BrowserExtensionServiceClientID(
                "\(extensionID).space.\(spaceID.rawValue.uuidString.lowercased())"
            )
        else {
            preconditionFailure("Unable to construct extension service identity")
        }
        return clientID
    }

    static func < (
        lhs: BrowserExtensionServiceClientID,
        rhs: BrowserExtensionServiceClientID
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
