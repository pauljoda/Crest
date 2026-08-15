import Foundation

enum BrowserSyncTombstoneReason: String, Codable, Equatable, Sendable {
    case explicitDelete
    case superseded
    case retention
}
