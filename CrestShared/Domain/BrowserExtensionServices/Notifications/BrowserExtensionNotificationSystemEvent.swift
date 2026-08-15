import Foundation

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
