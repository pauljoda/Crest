import Foundation
import Observation

@Observable
@MainActor
final class BrowserStore {
    /// The core-owned browsing data. It carries no selection; what this window
    /// shows is `window`.
    #if DEBUG
        var session: BrowserSession {
            get { family.currentSession }
            // Existing test fixtures replace synthetic sessions. Release
            // compositions expose only the core-owned read projection.
            set { family.replaceSessionForTesting(newValue, from: self) }
        }
    #else
        var session: BrowserSession { family.currentSession }
    #endif
    /// This window in the core's device, which owns what it shows.
    let windowID: BrowserWindowID
    private(set) var sessionRevision = 0
    var localSyncErrorDescription: String?
    let browsingMode: BrowserBrowsingMode
    let tabMultiSelection = BrowserTabMultiSelection()
    let family: BrowserStoreFamily
    /// The process's core, which every window of every browsing mode shares.
    @ObservationIgnored let core: CrestCore
    @ObservationIgnored let credentialVault: any CredentialVault
    @ObservationIgnored let syncCoordinator: BrowserSyncCoordinator?
    @ObservationIgnored var credentialSaveOperations: [BrowserCredentialSaveKey: BrowserCredentialSaveOperation] = [:]
    @ObservationIgnored let linkPreferences: BrowserLinkPreferenceStore
    @ObservationIgnored var pendingMovedTabActivation: BrowserTabRuntimeAssignment?
    @ObservationIgnored weak var interactionObserver: (any BrowserStoreInteractionObserving)?
    @ObservationIgnored weak var tabLinkProvider: (any BrowserTabLinkProviding)?
    @ObservationIgnored weak var tabCopying: (any BrowserTabCopying)?
    /// What this window showed when it last followed the core, which it keeps
    /// showing once the core no longer has it open.
    @ObservationIgnored private var lastWindow: WindowState
    @ObservationIgnored private var isClosed = false

    /// What the core says this window shows.
    var window: WindowState { core.state.windows[windowID.rawValue]?.value ?? lastWindow }

    var deletingSpaceIDs: Set<SpaceID> { family.deletingSpaceIDs }
    var selectedSpaceID: SpaceID { window.shownSpace }
    var selectedSpace: BrowserSpace? {
        guard !deletingSpaceIDs.contains(selectedSpaceID) else { return nil }
        return family.currentSession.space(id: selectedSpaceID)
    }
    var selectedTab: BrowserTab? {
        guard let space = selectedSpace, let tabID = window.shownTabID(in: space.id) else { return nil }
        return space.tabs.first { $0.id == tabID }
    }

    /// The tab this window shows in a Space, if any.
    func selectedTabID(in spaceID: SpaceID) -> TabID? {
        window.shownTabID(in: spaceID)
    }

    /// The session as this window renders it: the core's data and what the
    /// core says this window shows.
    var presented: BrowserPresentedSession {
        BrowserPresentedSession(session: session, window: window)
    }
    var isPrivateBrowsing: Bool { browsingMode.isPrivate }
    var isTemporaryWorkspace: Bool { temporarySourceAssignment != nil }
    var temporarySourceAssignment: BrowserSpaceRuntimeAssignment? { family.temporarySourceAssignment }
    var pendingSyncRecordCount: Int {
        guard !session.hasDisposableSeedState else { return 0 }
        return syncCoordinator?.journal.pendingRecordIDs.count ?? 0
    }
    var localSyncCoordinatorStatus: BrowserSyncCoordinatorStatus? { syncCoordinator?.status }

    /// Shows a Space in this window, on the tab it last showed there or the
    /// Space's fallback.
    func selectPresentedSpace(_ id: SpaceID) {
        guard !deletingSpaceIDs.contains(id), session.space(id: id) != nil else { return }
        guard sendWindowIntent(ShowSpace(windowID: windowID.rawValue, spaceID: id.rawValue)) else { return }
        tabMultiSelection.clear()
        sessionRevision &+= 1
    }

    func clearPresentedTabSelection(in spaceID: SpaceID) {
        guard sendWindowIntent(ShowTab(windowID: windowID.rawValue, spaceID: spaceID.rawValue, tabID: nil)) else {
            return
        }
        sessionRevision &+= 1
    }

    /// Shows a tab in this window and records when it was last used, which
    /// current-tab cleanup reads. Answers false when the core would not show it.
    @discardableResult
    func activateSessionTab(_ id: TabID, in spaceID: SpaceID) -> Bool {
        guard !deletingSpaceIDs.contains(spaceID), session.space(id: spaceID)?.contains(id) == true,
            sendWindowIntent(ShowTab(windowID: windowID.rawValue, spaceID: spaceID.rawValue, tabID: id.rawValue))
        else { return false }
        sessionRevision &+= 1
        return true
    }

    /// Stops showing a tab the session keeps: the window returns to the tab it
    /// showed before in that Space, or shows nothing there.
    func dismissShownTab(_ id: TabID, in spaceID: SpaceID) {
        guard
            sendWindowIntent(
                DismissShownTab(windowID: windowID.rawValue, spaceID: spaceID.rawValue, tabID: id.rawValue))
        else { return }
        sessionRevision &+= 1
    }

    /// The column shares this window keeps for a split group it resized.
    func resizeSplitColumns(_ fractions: [Double], for groupID: SplitGroupID) {
        sendWindowIntent(ResizeSplitColumns(windowID: windowID.rawValue, groupID: groupID.rawValue, shares: fractions))
    }

    /// Runs one intent about this window. What it changed, including a tab
    /// use the core recorded, reaches the family's session copy through the
    /// core's changes. Answers false when a rule refused it.
    @discardableResult
    private func sendWindowIntent(_ intent: some Intent) -> Bool {
        do { try core.send(intent) } catch { return false }
        lastWindow = window
        return true
    }

    /// A window over a new family holding `session`. Without `spaceID` it opens
    /// on the launch Space and its fallback tab; with one it shows that Space
    /// and only the `tabs` named.
    convenience init(
        session: BrowserSession,
        showing spaceID: SpaceID? = nil,
        tabs: [SpaceID: TabID] = [:],
        credentialVault: any CredentialVault = InMemoryCredentialVault(),
        syncCoordinator: BrowserSyncCoordinator? = nil,
        browsingMode: BrowserBrowsingMode = .standard,
        linkPreferences: BrowserLinkPreferenceStore = .shared,
        core: CrestCore = CrestCore()
    ) {
        self.init(
            opening: BrowserWindowOpening(showingSpaceID: spaceID, showingTabs: tabs, restoresTabs: spaceID == nil),
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            browsingMode: browsingMode,
            family: BrowserStoreFamily(session: session, browsingMode: browsingMode, core: core),
            linkPreferences: linkPreferences,
            core: core
        )
    }

    /// Opens a window over `family`'s session in `core`'s device as `opening`
    /// says.
    init(
        opening: BrowserWindowOpening = BrowserWindowOpening(),
        credentialVault: any CredentialVault,
        syncCoordinator: BrowserSyncCoordinator?,
        browsingMode: BrowserBrowsingMode,
        family: BrowserStoreFamily,
        linkPreferences: BrowserLinkPreferenceStore = .shared,
        core: CrestCore
    ) {
        windowID = opening.id
        self.linkPreferences = linkPreferences
        self.core = core
        self.credentialVault = credentialVault
        self.syncCoordinator = syncCoordinator
        self.browsingMode = browsingMode
        self.family = family
        localSyncErrorDescription = nil
        lastWindow = WindowState(
            id: opening.id.rawValue, workspaceID: UUID(), shownSpaceID: UUID(), shownTabs: [], splitColumnShares: [])
        let workspace = family.register(self)
        do {
            try core.send(
                OpenWindow(
                    windowID: opening.id.rawValue, workspaceID: workspace,
                    saved: opening.saved && family.keepsWindowRecords, copyingWindowID: opening.copying?.rawValue,
                    showingSpaceID: opening.showingSpaceID?.rawValue,
                    showingTabs: opening.showingTabs.map {
                        ShownTab(spaceID: $0.key.rawValue, tabID: $0.value.rawValue)
                    },
                    restoresTabs: opening.restoresTabs))
        } catch {
            preconditionFailure("The core refused to open a window over its own workspace: \(error)")
        }
        lastWindow = window
    }

    /// Closes this window in the core's device. What it showed stays readable
    /// for anything still holding the store.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        lastWindow = window
        _ = try? core.send(CloseWindow(windowID: windowID.rawValue))
    }

    isolated deinit {
        close()
    }
}

// MARK: - Lifecycle

extension BrowserStore {
    func resetPrivateBrowsingSession() {
        guard isPrivateBrowsing else { return }
        credentialSaveOperations.removeAll()
        family.resetDeletionState()
        interactionObserver?.browserWillResetSession()
        guard
            family.send(
                ResetPrivateBrowsing(workspaceID: family.workspaceID, windowID: windowID.rawValue), from: self,
                failure: "Core Space command failed")
        else { return }
        localSyncErrorDescription = nil
    }

    /// Another window over this family's session. Without a record of its own
    /// it starts as this window shows, unless `opening` names another.
    func makeWindowStore(_ opening: BrowserWindowOpening = BrowserWindowOpening()) -> BrowserStore {
        var opening = opening
        opening.copying = opening.copying ?? windowID
        let store = BrowserStore(
            opening: opening,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            browsingMode: browsingMode,
            family: family,
            linkPreferences: linkPreferences,
            core: core
        )
        store.localSyncErrorDescription = localSyncErrorDescription
        return store
    }
}

// MARK: - Persistence

extension BrowserStore {
    func mergeRemoteSyncRecords(_ records: [BrowserSyncRecord]) throws {
        guard let syncCoordinator else { return }
        _ = try syncCoordinator.merge(remoteRecords: records, into: session) { next, transaction in
            try self.family.installSyncedSession(next, transaction: transaction, from: self)
        }
        localSyncErrorDescription = nil
    }

    func prepareToOverwriteCloud(with remoteRecords: [BrowserSyncRecord]) throws {
        guard let syncCoordinator else { return }
        try syncCoordinator.prepareToOverwriteCloud(with: session, remoteRecords: remoteRecords)
        localSyncErrorDescription = nil
    }

    func replaceLocalWithCloud(_ remoteRecords: [BrowserSyncRecord]) throws {
        guard let syncCoordinator else { return }
        _ = try syncCoordinator.replaceLocalWithCloud(remoteRecords, replacing: session) { next, transaction in
            try self.family.installSyncedSession(next, transaction: transaction, from: self)
        }
        localSyncErrorDescription = nil
    }

    func replaceDisposableSeedWithCloud(_ remoteRecords: [BrowserSyncRecord]) throws {
        guard session.hasDisposableSeedState else { return }
        try replaceLocalWithCloud(remoteRecords)
    }

    /// Returns once the sync stages the core queued for edits accepted before
    /// the call have finished and every such edit is on disk, or a save has
    /// failed. Quitting and backgrounding wait for it.
    func flushPendingSyncPersistence() async {
        await syncCoordinator?.staged()
        await family.flushPendingSaves()
    }

    /// Flushes again after any pass the session changed during, so an edit
    /// still on its way when quitting or backgrounding began, such as a link
    /// being opened or a page's settling title, is saved and staged too.
    /// Callers bound the wait with `BrowserPersistenceFlush`.
    func flushPendingSyncPersistenceUntilSettled() async {
        var revision: Int
        repeat {
            revision = sessionRevision
            await flushPendingSyncPersistence()
        } while sessionRevision != revision
    }

    /// The family accepted a change. The core's device has already moved or
    /// repaired this window; a window that now shows another Space, or its
    /// Space under another profile or policy, drops its multi-selection.
    func receiveFamilySessionChange(from previous: BrowserSession, to shared: BrowserSession) {
        let previousSpaceID = lastWindow.shownSpace
        let previousSpace = previous.space(id: previousSpaceID)
        let selectedSpace = shared.space(id: selectedSpaceID)
        if previousSpaceID != selectedSpaceID
            || previousSpace?.profile.id != selectedSpace?.profile.id
            || previousSpace?.accessPolicy != selectedSpace?.accessPolicy
        {
            tabMultiSelection.clear()
        }
        if let activation = pendingMovedTabActivation,
            selectedSpaceID != activation.spaceID
                || selectedTabID(in: activation.spaceID) != activation.tabID
                || selectedSpace?.profile.id != activation.profileID
        {
            pendingMovedTabActivation = nil
        }
        lastWindow = window
        sessionRevision &+= 1
    }
}

// MARK: - Cloud Sync Model

@MainActor
extension BrowserStore: BrowserCloudSyncModelGateway {
    func cloudSyncRecords() async -> [BrowserSyncRecord] {
        guard !session.hasDisposableSeedState, let syncCoordinator else { return [] }
        await syncCoordinator.staged()
        return await Task.detached(priority: .utility) { syncCoordinator.journal.records }.value
    }

    func cloudSyncPendingRecordIDs() async -> Set<BrowserSyncRecordID> {
        guard !session.hasDisposableSeedState, let syncCoordinator else { return [] }
        await syncCoordinator.staged()
        return await Task.detached(priority: .utility) { syncCoordinator.journal.pendingRecordIDs }.value
    }

    func mergeCloudSyncRecords(_ records: [BrowserSyncRecord]) async throws {
        do {
            // The merge and its journal are on disk when this returns, so the
            // transport may keep the server token that covers them.
            try mergeRemoteSyncRecords(records)
        } catch {
            localSyncErrorDescription = String(describing: error)
            throw error
        }
    }

    func markCloudSyncRecordsUploaded(
        _ acknowledgedVersions: [BrowserSyncRecordID: BrowserSyncVersion]
    ) async throws {
        guard let syncCoordinator else { return }
        try await Task.detached(priority: .utility) {
            try syncCoordinator.markUploaded(acknowledgedVersions)
        }.value
    }
}

// MARK: - Cloud Sync Workflow

@MainActor
extension BrowserStore: BrowserCloudSyncWorkflowGateway {
    var hasDisposableCloudSyncSeed: Bool { session.hasDisposableSeedState }

    var cloudSyncLocalRecordCount: Int {
        syncCoordinator?.journal.records.count ?? 0
    }

    var cloudSyncPendingRecordCount: Int { pendingSyncRecordCount }

    /// Why the core could not stage the latest edits for sync, or the last
    /// local sync failure this window saw.
    var cloudSyncLocalErrorDescription: String? {
        core.state.syncStagingFailure.map { String(localized: $0.title) } ?? localSyncErrorDescription
    }
}
