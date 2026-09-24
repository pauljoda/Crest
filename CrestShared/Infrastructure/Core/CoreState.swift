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
    /// The newest session revision the core has on disk; zero before its
    /// first save and for a core that keeps nothing.
    var savedRevision: Int64 = 0
    /// Why the core's last save failed, until a later save succeeds.
    var storageFailure: StorageFailure?
}
