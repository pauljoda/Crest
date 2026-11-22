import Foundation

struct BrowserHostedWebNotificationDelivery: Equatable, Sendable {
    /// The most of a page's title and body a notification shows.
    static let maximumTitleLength = 200
    static let maximumBodyLength = 1_000

    let identifier: String
    let title: String
    let body: String
    let origin: SiteOrigin
    let isSilent: Bool
}

enum BrowserHostedWebNotificationEvent: Equatable, Sendable {
    case clicked
}
