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
    @ObservationIgnored let syncCoalescingDelay: Duration
    @ObservationIgnored var cloudSyncChangeHandler: (@Sendable () -> Void)?
    @ObservationIgnored var syncStageGeneration = 0
    @ObservationIgnored var syncStageTask: Task<Void, Never>?
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
    var window: WindowState { core.state.windows[windowID.rawValue] ?? lastWindow }

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
        syncCoalescingDelay: Duration = .milliseconds(150),
        browsingMode: BrowserBrowsingMode = .standard,
        linkPreferences: BrowserLinkPreferenceStore = .shared,
        core: CrestCore = CrestCore()
    ) {
        self.init(
            opening: BrowserWindowOpening(showingSpaceID: spaceID, showingTabs: tabs, restoresTabs: spaceID == nil),
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            syncCoalescingDelay: syncCoalescingDelay,
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
        syncCoalescingDelay: Duration,
        browsingMode: BrowserBrowsingMode,
        family: BrowserStoreFamily,
        cloudSyncChangeHandler: (@Sendable () -> Void)? = nil,
        linkPreferences: BrowserLinkPreferenceStore = .shared,
        core: CrestCore
    ) {
        windowID = opening.id
        self.linkPreferences = linkPreferences
        self.core = core
        self.credentialVault = credentialVault
        self.syncCoordinator = syncCoordinator
        self.syncCoalescingDelay = syncCoalescingDelay
        self.browsingMode = browsingMode
        self.family = family
        self.cloudSyncChangeHandler = cloudSyncChangeHandler
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
        syncStageTask?.cancel()
        syncStageTask = nil
        syncStageGeneration = 0
        credentialSaveOperations.removeAll()
        family.resetDeletionState()
        interactionObserver?.browserWillResetSession()
        let template = BrowserSessionArguments.SpaceTemplate(template: BrowserSession.privateBrowsing().spaces[0])
        guard family.executeSpace(.spaceResetPrivate, arguments: template, from: self) else { return }
        localSyncErrorDescription = nil
        let revision = family.publish(session, from: self)
        syncCoordinator?.advanceStoreRevision(to: revision)
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
            syncCoalescingDelay: syncCoalescingDelay,
            browsingMode: browsingMode,
            family: family,
            cloudSyncChangeHandler: cloudSyncChangeHandler,
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
        let revision = family.reserveSyncRevision()
        syncCoordinator.advanceStoreRevision(to: revision)
        _ = try syncCoordinator.merge(remoteRecords: records, into: session, storeRevision: revision) {
            next, transaction in
            try self.family.installSyncedSession(next, transaction: transaction, from: self)
        }
        family.publish(session, from: self, at: revision)
        localSyncErrorDescription = nil
    }

    func prepareToOverwriteCloud(with remoteRecords: [BrowserSyncRecord]) throws {
        guard let syncCoordinator else { return }
        let revision = family.reserveSyncRevision()
        syncCoordinator.advanceStoreRevision(to: revision)
        try syncCoordinator.prepareToOverwriteCloud(
            with: session,
            remoteRecords: remoteRecords,
            storeRevision: revision
        )
        localSyncErrorDescription = nil
    }

    func replaceLocalWithCloud(_ remoteRecords: [BrowserSyncRecord]) throws {
        guard let syncCoordinator else { return }
        let revision = family.reserveSyncRevision()
        syncCoordinator.advanceStoreRevision(to: revision)
        _ = try syncCoordinator.replaceLocalWithCloud(remoteRecords, replacing: session, storeRevision: revision) {
            next, transaction in
            try self.family.installSyncedSession(next, transaction: transaction, from: self)
        }
        family.publish(session, from: self, at: revision)
        localSyncErrorDescription = nil
    }

    func replaceDisposableSeedWithCloud(_ remoteRecords: [BrowserSyncRecord]) throws {
        guard session.hasDisposableSeedState else { return }
        try replaceLocalWithCloud(remoteRecords)
    }

    func setCloudSyncChangeHandler(_ handler: (@Sendable () -> Void)?) {
        cloudSyncChangeHandler = handler
    }

    /// Returns once the sync staging this window started has finished and
    /// every edit accepted before the call is on disk, or a save has failed.
    /// Quitting and backgrounding wait for it.
    func flushPendingSyncPersistence() async {
        await syncStageTask?.value
        await family.flushPendingSaves()
    }

    func beginInitialSyncStaging(
        session snapshot: BrowserSession,
        deletionReason: BrowserSyncTombstoneReason = .retention
    ) {
        guard let syncCoordinator, !snapshot.hasDisposableSeedState else { return }
        let generation = syncStageGeneration
        let storeRevision = BrowserStoreSyncRevision.initial
        syncCoordinator.advanceStoreRevision(to: storeRevision)

        syncStageTask = Task { @MainActor [weak self] in
            do {
                let staged = try await syncCoordinator.stageInBackground(
                    session: snapshot,
                    deletionReason: deletionReason,
                    storeRevision: storeRevision
                )
                guard self?.syncStageGeneration == generation else { return }
                self?.localSyncErrorDescription = nil
                if staged {
                    self?.cloudSyncChangeHandler?()
                }
            } catch {
                guard self?.syncStageGeneration == generation else { return }
                self?.localSyncErrorDescription = String(describing: error)
            }
        }
    }

    /// Stages sync after an accepted edit. The core already saves every edit
    /// it accepts; this orders the window's background staging after it, with
    /// the edit's deletion reason and urgency.
    ///
    /// TRANSITIONAL: staging moves into the core when session intents land,
    /// because each intent's handler knows its own deletion reason and urgency.
    /// These call sites then go away.
    func stageSync(
        deletionReason: BrowserSyncTombstoneReason = .superseded,
        urgency syncUrgency: BrowserStoreSyncStageUrgency = .immediate
    ) {
        let storeRevision = family.publish(session, from: self)
        syncCoordinator?.advanceStoreRevision(to: storeRevision)
        guard let syncCoordinator, !session.hasDisposableSeedState else { return }

        syncStageGeneration += 1
        let generation = syncStageGeneration
        let sessionSnapshot = session
        let previousTask = syncStageTask
        let coalescingDelay = syncCoalescingDelay

        syncStageTask = Task { @MainActor [weak self] in
            if syncUrgency == .coalesced, coalescingDelay > .zero {
                try? await Task.sleep(for: coalescingDelay)
            }
            await previousTask?.value
            guard syncUrgency == .immediate || self?.syncStageGeneration == generation else {
                return
            }
            do {
                let staged = try await syncCoordinator.stageInBackground(
                    session: sessionSnapshot,
                    deletionReason: deletionReason,
                    storeRevision: storeRevision
                )
                self?.localSyncErrorDescription = nil
                if staged {
                    self?.cloudSyncChangeHandler?()
                }
            } catch {
                self?.localSyncErrorDescription = String(describing: error)
            }
        }
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

    func invalidatePendingSyncStage() {
        syncStageGeneration &+= 1
    }
}

// MARK: - Cloud Sync Model

@MainActor
extension BrowserStore: BrowserCloudSyncModelGateway {
    func cloudSyncRecords() async -> [BrowserSyncRecord] {
        guard !session.hasDisposableSeedState else { return [] }
        await syncStageTask?.value
        return syncCoordinator?.journal.records ?? []
    }

    func cloudSyncPendingRecordIDs() async -> Set<BrowserSyncRecordID> {
        guard !session.hasDisposableSeedState else { return [] }
        await syncStageTask?.value
        return syncCoordinator?.journal.pendingRecordIDs ?? []
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

    var cloudSyncLocalErrorDescription: String? { localSyncErrorDescription }
}
