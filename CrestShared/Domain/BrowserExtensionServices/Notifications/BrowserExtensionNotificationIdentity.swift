import Foundation

/// The pair that uniquely names one emulated notification.
///
/// Extension-authored notification identifiers are only unique within their own
/// extension — two extensions may both post `"update-available"` — so the host
/// notification center is addressed by this pair rather than by the raw
/// extension-supplied identifier.
struct BrowserExtensionNotificationIdentity: Equatable, Hashable, Sendable {
    let client: BrowserExtensionServiceClientID
    let notificationIdentifier: String
}
