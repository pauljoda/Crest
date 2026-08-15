import Foundation

/// A notification resolved down to the flat identifiers and content the host
/// notification center needs.
///
/// Every extension-facing concern — identity encoding, authorization gating,
/// per-client bookkeeping — has already been applied by the time a delivery
/// reaches ``BrowserExtensionNotificationCentering``, which keeps the platform
/// adapter free of routing rules.
struct BrowserExtensionNotificationDelivery: Equatable, Hashable, Sendable {
    let systemIdentifier: String
    let threadIdentifier: String
    let categoryIdentifier: String
    let title: String
    let body: String
    let iconData: Data?
    let buttonTitles: [String]
}
