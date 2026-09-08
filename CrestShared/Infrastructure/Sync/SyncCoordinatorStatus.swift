import Foundation

enum BrowserSyncCoordinatorStatus: Equatable, Sendable {
    case ready
    case recoveredCorruptLocalJournal
}
