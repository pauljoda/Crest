import Foundation

/// Framework-neutral projection of the host notification authorization state.
///
/// `chrome.notifications.create` has no authorization concept of its own, so the
/// emulation layer maps Crest's own system authorization onto a posting outcome
/// rather than surfacing a separate permission prompt to extension code.
enum BrowserExtensionNotificationAuthorization: Equatable, Hashable, Sendable {
    case notDetermined
    case authorized
    case denied

    /// Whether a delivery attempt can reach the notification center.
    var allowsDelivery: Bool {
        self == .authorized
    }
}
