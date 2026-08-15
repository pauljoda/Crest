import Foundation

/// The result of a posting attempt.
///
/// A denied authorization is an ordinary outcome rather than an error: an
/// extension that calls `chrome.notifications.create` while Crest itself is
/// muted in System Settings should receive a quiet negative answer, not a
/// rejected promise that its background script is unlikely to handle.
enum BrowserExtensionNotificationPostOutcome: Equatable, Hashable, Sendable {
    case presented(BrowserExtensionNotificationIdentity)
    case authorizationDenied
    case rejected(description: String)

    /// The identity the host accepted, when the notification was presented.
    var presentedIdentity: BrowserExtensionNotificationIdentity? {
        guard case .presented(let identity) = self else { return nil }
        return identity
    }
}
