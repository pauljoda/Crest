import Foundation

enum BrowserSitePermissionDecision: String, Codable, Equatable, Sendable {
    case ask
    case grantForSession
    case denyForSession
    case grantPersistently
    case denyPersistently

}
