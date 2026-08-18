import Foundation

enum TabArchiveReason: String, Codable, Equatable, Sendable {
    case autoCleanup
    case closed
    /// A saved or pinned tab the person deliberately deleted. Unlike a close,
    /// this is the durable evidence that authorizes an explicit sync tombstone.
    case deleted
    /// Local presentation for an explicit deletion first confirmed by another
    /// device. Projection sends it back as `deleted`, never as a new cause.
    case deletedOnAnotherDevice
    case quickWindow
    /// Local presentation metadata for an archive record first observed from
    /// another device. Projection canonicalizes this to `closed` so one
    /// device's observation never becomes the removal cause everywhere.
    case synced

    var syncProjectionReason: Self {
        switch self {
        case .synced:
            .closed
        case .deletedOnAnotherDevice:
            .deleted
        default:
            self
        }
    }

    var isExplicitDeletion: Bool {
        self == .deleted || self == .deletedOnAnotherDevice
    }
}
