import Foundation

enum BrowserSpaceAccessPolicy: String, Codable, Equatable, Sendable {
    case open
    case deviceOwnerAuthentication

    var requiresAuthentication: Bool {
        self == .deviceOwnerAuthentication
    }
}
