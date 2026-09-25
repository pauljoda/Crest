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
    /// What the stored session's sync journal holds, as the core last
    /// published it: its records and those waiting to upload. Nil until the
    /// core attaches the journal, and for a core that keeps nothing.
    var syncJournal: SyncJournalChanged?
    /// The site permission choices each Space keeps, in the order the settings
    /// list them, as the core last published them. A Space missing here keeps
    /// none.
    var sitePermissions: [UUID: [SitePermissionRecordState]] = [:]
    /// Advances with every site permission change the core publishes, so a
    /// view that asks the core for a decision redraws when any choice changes.
    var sitePermissionRevision: UInt64 = 0
    /// The keys each command this device offers answers to, in the order the
    /// settings list them, as the core last published them.
    var shortcutBindings: [ShortcutBinding] = []
    /// The same bindings, by command.
    var shortcuts: [ShortcutCommand: ShortcutBinding] = [:]
    /// Whether the person changed any shortcut, including one this device
    /// does not offer.
    var shortcutsAreCustomized = false
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
    /// TRANSITIONAL until S6.7: the workspaces whose session the batch being
    /// applied has changed so far, which `CrestCore` reports and clears once
    /// the batch is applied.
    @ObservationIgnored var touchedWorkspaces: Set<UUID> = []
}
