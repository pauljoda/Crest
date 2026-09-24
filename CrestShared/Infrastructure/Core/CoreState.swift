import Foundation
import Observation

/// The Swift read model of the core's state. Views read it directly; only the
/// changes `CrestCore` receives update it, each through its applier in a
/// `CoreState+Area.swift` file.
@MainActor
@Observable
final class CoreState {
    // MARK: - Variables

    /// This run's download records, newest first.
    var downloads: [DownloadState] = []
    /// What each open window shows, by window.
    var windows: [UUID: WindowState] = [:]
    /// Each page this device hosts, by page: its owner, its engine and where
    /// it stands there.
    var pages: [UUID: PageState] = [:]
    /// The newest session revision the core has on disk; zero before its
    /// first save and for a core that keeps nothing.
    var savedRevision: Int64 = 0
    /// Why the core's last save failed, until a later save succeeds.
    var storageFailure: StorageFailure?
    /// Why the core could not stage the session's latest edits for sync, until
    /// a later stage succeeds.
    var syncStagingFailure: SyncStagingFailure?
    /// TRANSITIONAL until S6.1: the Swift session copy of each attached
    /// workspace, which its session changes update.
    @ObservationIgnored var sessionCopies: [UUID: SessionCopy] = [:]
    /// TRANSITIONAL until S6.1: the image bytes of tabs a change in the batch
    /// being applied removed, by tab, for a later change that places the tab
    /// again, in this workspace or another.
    @ObservationIgnored var detachedImages: [UUID: Data] = [:]
}
