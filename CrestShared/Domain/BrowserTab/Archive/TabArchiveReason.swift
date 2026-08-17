import Foundation

enum TabArchiveReason: String, Codable, Equatable, Sendable {
    case autoCleanup
    case closed
    case quickWindow
    /// Local presentation metadata for an archive record first observed from
    /// another device. Projection canonicalizes this to `closed` so one
    /// device's observation never becomes the removal cause everywhere.
    case synced

    var syncProjectionReason: Self {
        self == .synced ? .closed : self
    }
}
