import Foundation

/// One installed extension an update pass may act on.
///
/// A target is identified by the pair that actually owns an installation —
/// the Space and the extension — because the same extension installed in two
/// Spaces is two separate packages with separate permissions, and each is
/// updated on its own.
struct BrowserExtensionUpdateTarget: Equatable, Identifiable, Sendable {
    let extensionID: String
    let spaceID: SpaceID
    let displayName: String
    let installedVersion: String?
    let isEnabled: Bool

    var id: String {
        "\(spaceID.rawValue.uuidString.lowercased())/\(extensionID)"
    }
}
