import Foundation

/// A notification interaction routed back to the extension that posted it.
struct BrowserExtensionNotificationEvent: Equatable, Hashable, Sendable {
    let identity: BrowserExtensionNotificationIdentity
    let kind: BrowserExtensionNotificationEventKind
}
