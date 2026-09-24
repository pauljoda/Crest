import Foundation
import Observation

/// The Swift read model of the core's state. Views read it directly; only the
/// changes `CrestCore` receives update it, each through its applier in a
/// `CoreState+Area.swift` file. It is observable per entity: each workspace,
/// Space, tab, folder and window is an object of its own that notifies only
/// when one of its values really changes.
@MainActor
@Observable
final class CoreState {
    // MARK: - Variables

    /// Each workspace attached to this device, by workspace. The dictionary
    /// changes only when a workspace joins or leaves.
    var workspaces: [UUID: WorkspaceModel] = [:]
    /// The images tabs wear, which the platform keeps and the core never sees.
    let favicons = FaviconAssets()
    /// This run's download records, newest first.
    var downloads: [DownloadState] = []
    /// What each open window shows, by window. The dictionary changes only
    /// when a window opens or closes.
    var windows: [UUID: WindowStateModel] = [:]
    /// Each page this device hosts, by page: its owner, its engine, where it
    /// stands there and its live state. The dictionary changes only when a
    /// page opens or goes, so a page's new title redraws only its readers.
    var pages: [UUID: PageStateModel] = [:]
    /// The newest file revision the core has on disk, counting the stored
    /// session's edits and this device's saved windows; zero before its first
    /// save and for a core that keeps nothing.
    var savedRevision: Int64 = 0
    /// Why the core's last save failed, until a later save succeeds.
    var storageFailure: StorageFailure?
    /// Why the core could not stage the session's latest edits for sync, until
    /// a later stage succeeds.
    var syncStagingFailure: SyncStagingFailure?
    /// This process's access to each Space profile that holds a grant or is
    /// waiting on the device owner, as the core last published it. A profile
    /// missing here holds no grant. Stored before it is announced; see
    /// `BrowserStoreFirstObservable`.
    var spaceAccess: [BrowserSpaceRuntimeAssignment: SpaceLockChanged] {
        observed(\.spaceAccessStorage, as: \.spaceAccess)
    }
    @ObservationIgnored var spaceAccessStorage: [BrowserSpaceRuntimeAssignment: SpaceLockChanged] = [:]
    /// TRANSITIONAL until S6.7 deletes the Swift session copy: the copy of
    /// each attached workspace, which its session changes update.
    @ObservationIgnored var sessionCopies: [UUID: SessionCopy] = [:]
}
