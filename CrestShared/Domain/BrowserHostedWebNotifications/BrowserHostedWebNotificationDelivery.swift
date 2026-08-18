import Foundation

struct BrowserHostedWebNotificationDelivery: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let origin: BrowserSiteOrigin
    let isSilent: Bool
}
