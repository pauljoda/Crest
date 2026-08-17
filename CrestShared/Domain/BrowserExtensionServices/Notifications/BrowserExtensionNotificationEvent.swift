import Foundation

/// A notification interaction routed back to the extension that posted it.
struct BrowserExtensionNotificationEvent: Equatable, Hashable, Sendable {
    let identity: BrowserExtensionNotificationIdentity
    let kind: BrowserExtensionNotificationEventKind
}

/// The interaction that a delivered notification reported back.
///
/// Cases map onto `chrome.notifications.onClicked`, `onButtonClicked`, and
/// `onClosed` respectively.
enum BrowserExtensionNotificationEventKind: Equatable, Hashable, Sendable {
    case clicked
    case buttonClicked(index: Int)
    case dismissed(byUser: Bool)
}

/// A notification interaction as the host reports it, before the owning
/// extension has been resolved.
///
/// The host knows only the flat system identifier it was given at delivery
/// time; ``BrowserExtensionNotificationIdentityCodec`` turns that back into an
/// owning client.
struct BrowserExtensionNotificationSystemEvent: Equatable, Hashable, Sendable {
    let systemIdentifier: String
    let kind: BrowserExtensionNotificationEventKind
}
