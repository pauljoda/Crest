import Foundation
import Observation

/// The Swift read model of the core's state. Views read it directly; only the
/// changes `CrestCore` receives update it, each through its applier in a
/// `CoreState+Area.swift` file. It is observable per entity: each workspace,
/// Space, tab, folder and window is an object of its own that notifies only
/// when one of its values really changes.
///
/// Every value is stored before it is announced, so a view that renders
/// while a change is announced reads the new value; see
/// `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class CoreState {
    // MARK: - Variables

    /// Each workspace attached to this device, by workspace. The dictionary
    /// changes only when a workspace joins or leaves.
    var workspaces: [UUID: WorkspaceModel] { observed(\.workspacesStorage, as: \.workspaces) }
    @ObservationIgnored var workspacesStorage: [UUID: WorkspaceModel] = [:]
    /// The images tabs wear, which the platform keeps and the core never sees.
    let favicons = FaviconAssets()
    /// This run's download records, newest first.
    var downloads: [DownloadState] {
        get { observed(\.downloadsStorage, as: \.downloads) }
        set { publish(newValue, into: \.downloadsStorage, as: \.downloads) }
    }
    @ObservationIgnored private var downloadsStorage: [DownloadState] = []
    /// What each open window shows, by window. The dictionary changes only
    /// when a window opens or closes.
    var windows: [UUID: WindowStateModel] { observed(\.windowsStorage, as: \.windows) }
    @ObservationIgnored var windowsStorage: [UUID: WindowStateModel] = [:]
    /// Each page this device hosts, by page: its owner, its engine, where it
    /// stands there and its live state. The dictionary changes only when a
    /// page opens or goes, so a page's new title redraws only its readers.
    var pages: [UUID: PageStateModel] { observed(\.pagesStorage, as: \.pages) }
    @ObservationIgnored var pagesStorage: [UUID: PageStateModel] = [:]
    /// The newest file revision the core has on disk, counting the stored
    /// session's edits and this device's saved windows; zero before its first
    /// save and for a core that keeps nothing.
    var savedRevision: Int64 {
        get { observed(\.savedRevisionStorage, as: \.savedRevision) }
        set { publish(newValue, into: \.savedRevisionStorage, as: \.savedRevision) }
    }
    @ObservationIgnored private var savedRevisionStorage: Int64 = 0
    /// Why the core's last save failed, until a later save succeeds.
    var storageFailure: StorageFailure? {
        get { observed(\.storageFailureStorage, as: \.storageFailure) }
        set { publish(newValue, into: \.storageFailureStorage, as: \.storageFailure) }
    }
    @ObservationIgnored private var storageFailureStorage: StorageFailure?
    /// Why the core could not stage the session's latest edits for sync, until
    /// a later stage succeeds.
    var syncStagingFailure: SyncStagingFailure? {
        get { observed(\.syncStagingFailureStorage, as: \.syncStagingFailure) }
        set { publish(newValue, into: \.syncStagingFailureStorage, as: \.syncStagingFailure) }
    }
    @ObservationIgnored private var syncStagingFailureStorage: SyncStagingFailure?
    /// What the stored session's sync journal holds, as the core last
    /// published it: its records and those waiting to upload. Nil until the
    /// core attaches the journal, and for a core that keeps nothing.
    var syncJournal: SyncJournalChanged? {
        get { observed(\.syncJournalStorage, as: \.syncJournal) }
        set { publish(newValue, into: \.syncJournalStorage, as: \.syncJournal) }
    }
    @ObservationIgnored private var syncJournalStorage: SyncJournalChanged?
    /// The site permission choices each Space keeps, in the order the settings
    /// list them, as the core last published them. A Space missing here keeps
    /// none.
    var sitePermissions: [UUID: [SitePermissionRecordState]] {
        get { observed(\.sitePermissionsStorage, as: \.sitePermissions) }
        set { publish(newValue, into: \.sitePermissionsStorage, as: \.sitePermissions) }
    }
    @ObservationIgnored private var sitePermissionsStorage: [UUID: [SitePermissionRecordState]] = [:]
    /// Advances with every site permission change the core publishes, so a
    /// view that asks the core for a decision redraws when any choice changes.
    var sitePermissionRevision: UInt64 {
        get { observed(\.sitePermissionRevisionStorage, as: \.sitePermissionRevision) }
        set { publish(newValue, into: \.sitePermissionRevisionStorage, as: \.sitePermissionRevision) }
    }
    @ObservationIgnored private var sitePermissionRevisionStorage: UInt64 = 0
    /// The keys each command this device offers answers to, in the order the
    /// settings list them, as the core last published them.
    var shortcutBindings: [ShortcutBinding] {
        get { observed(\.shortcutBindingsStorage, as: \.shortcutBindings) }
        set { publish(newValue, into: \.shortcutBindingsStorage, as: \.shortcutBindings) }
    }
    @ObservationIgnored private var shortcutBindingsStorage: [ShortcutBinding] = []
    /// The same bindings, by command.
    var shortcuts: [ShortcutCommand: ShortcutBinding] {
        get { observed(\.shortcutsStorage, as: \.shortcuts) }
        set { publish(newValue, into: \.shortcutsStorage, as: \.shortcuts) }
    }
    @ObservationIgnored private var shortcutsStorage: [ShortcutCommand: ShortcutBinding] = [:]
    /// Whether the person changed any shortcut, including one this device
    /// does not offer.
    var shortcutsAreCustomized: Bool {
        get { observed(\.shortcutsAreCustomizedStorage, as: \.shortcutsAreCustomized) }
        set { publish(newValue, into: \.shortcutsAreCustomizedStorage, as: \.shortcutsAreCustomized) }
    }
    @ObservationIgnored private var shortcutsAreCustomizedStorage = false
    /// This process's access to each Space profile that holds a grant or is
    /// waiting on the device owner, as the core last published it. A profile
    /// missing here holds no grant.
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

extension CoreState: BrowserStoreFirstObservable {}
