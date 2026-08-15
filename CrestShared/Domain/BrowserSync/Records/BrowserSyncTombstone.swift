import Foundation

struct BrowserSyncTombstone: Codable, Equatable, Sendable {
    let reason: BrowserSyncTombstoneReason
    let deletedAt: Date
}
