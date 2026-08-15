import Foundation

/// What the durable session store found on the way in.
///
/// A store that cannot read what it wrote says so. Collapsing "nothing stored"
/// and "stored but unreadable" into one silent `nil` is how a version skew or a
/// truncated write turns into a fresh-install seed that then overwrites the very
/// bytes a later build could have read. This mirrors
/// `BrowserSyncCoordinatorStatus`: the load still succeeds with a usable
/// session, and the fact that something was rescued travels alongside it.
enum BrowserSessionPersistenceStatus: Equatable, Sendable {
    /// A readable session, or genuinely nothing stored yet.
    case ready
    /// A stored session refused to decode. Its bytes were copied aside before
    /// anything could overwrite them, and for the rest of this launch the store
    /// deletes nothing the unreadable session may still own.
    case preservedUnreadableSession
}
