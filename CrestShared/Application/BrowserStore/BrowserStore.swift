import Foundation
import Observation

@Observable
@MainActor
final class BrowserStore {
    /// The core-owned browsing data. It carries no selection; what this window
    /// shows is `selection`.
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
    /// The Space and tabs this window shows. Window records persist it; the core
    /// session never holds it.
    private(set) var selection: BrowserStoreSelection
    private(set) var sessionRevision = 0
    var localSyncErrorDescription: String?
    let browsingMode: BrowserBrowsingMode
    let tabMultiSelection = BrowserTabMultiSelection()
    let family: BrowserStoreFamily
    @ObservationIgnored let persistence: any BrowserSessionPersisting
    @ObservationIgnored let credentialVault: any CredentialVault
    @ObservationIgnored let syncCoordinator: BrowserSyncCoordinator?
    @ObservationIgnored let syncCoalescingDelay: Duration
    @ObservationIgnored var cloudSyncChangeHandler: (@Sendable () -> Void)?
    @ObservationIgnored var syncStageGeneration = 0
    @ObservationIgnored var syncStageTask: Task<Void, Never>?
    @ObservationIgnored var credentialSaveOperations: [BrowserCredentialSaveKey: BrowserCredentialSaveOperation] = [:]
    @ObservationIgnored var tabSelectionHistory: BrowserTabSelectionHistory
    @ObservationIgnored let linkPreferences: BrowserLinkPreferenceStore
    @ObservationIgnored var pendingMovedTabActivation: BrowserTabRuntimeAssignment?
    @ObservationIgnored weak var interactionObserver: (any BrowserStoreInteractionObserving)?
    @ObservationIgnored weak var tabLinkProvider: (any BrowserTabLinkProviding)?
    @ObservationIgnored weak var tabCopying: (any BrowserTabCopying)?

    var deletingSpaceIDs: Set<SpaceID> { family.deletingSpaceIDs }
    var selectedSpaceID: SpaceID { selection.selectedSpaceID }
    var selectedSpace: BrowserSpace? {
        guard !deletingSpaceIDs.contains(selection.selectedSpaceID) else {
            return nil
        }
        return selection.selectedSpace(in: family.currentSession)
    }
    var selectedTab: BrowserTab? {
        guard selectedSpace != nil else { return nil }
        return selection.selectedTab(in: family.currentSession)
    }

    /// The tab this window shows in a Space, if any.
    func selectedTabID(in spaceID: SpaceID) -> TabID? {
        selection.selectedTabID(in: spaceID)
    }

    /// The session as this window renders it: the core's data and this
    /// window's selection.
    var presented: BrowserPresentedSession {
        BrowserPresentedSession(session: session, selection: selection)
    }
    var isPrivateBrowsing: Bool { browsingMode.isPrivate }
    var isTemporaryWorkspace: Bool { temporarySourceAssignment != nil }
    var temporarySourceAssignment: BrowserSpaceRuntimeAssignment? { family.temporarySourceAssignment }
    var pendingSyncRecordCount: Int {
        guard !session.hasDisposableSeedState else { return 0 }
        return syncCoordinator?.journal.pendingRecordIDs.count ?? 0
    }
    var localSyncCoordinatorStatus: BrowserSyncCoordinatorStatus? { syncCoordinator?.status }

    /// The viewed Space and an empty tab selection belong to this window.
    /// A core command is only needed when saved tab data changes.
    func selectPresentedSpace(_ id: SpaceID) {
        guard !deletingSpaceIDs.contains(id), let space = session.space(id: id) else { return }
        selection.selectSpace(space)
        tabMultiSelection.clear()
        selectionDidChange()
    }

    func clearPresentedTabSelection(in spaceID: SpaceID) {
        selection.clearTab(in: spaceID)
        selectionDidChange()
    }

    /// Shows a tab in this window. Only the window's selection changes.
    func presentTab(_ tabID: TabID, in spaceID: SpaceID) {
        guard !deletingSpaceIDs.contains(spaceID), session.space(id: spaceID)?.contains(tabID) == true else { return }
        selection.selectTab(tabID, in: spaceID)
        selectionDidChange()
    }

    /// Adopts the tabs a window record remembers for each Space at launch.
    /// Launch keeps opening the Space it chose (the default Space), as it
    /// always has; only the per-Space tabs come from the record.
    func restoreLaunchSelection(tabsFrom record: BrowserWindowState) {
        var restored = BrowserStoreSelection(
            selectedSpaceID: selection.selectedSpaceID, selectedTabIDsBySpace: record.selection.tabSelections)
        restored.reconcile(using: session, excluding: deletingSpaceIDs)
        if let space = restored.selectedSpace(in: session) { restored.selectSpace(space) }
        selection = restored
        tabMultiSelection.clear()
        selectionDidChange()
    }

    private func selectionDidChange() {
        sessionRevision &+= 1
        tabSelectionHistory.reconcile(session: session, selection: selection)
    }

    convenience init(
        session: BrowserSession,
        selection: BrowserStoreSelection? = nil,
        persistence: any BrowserSessionPersisting,
        credentialVault: any CredentialVault = InMemoryCredentialVault(),
        syncCoordinator: BrowserSyncCoordinator? = nil,
        syncCoalescingDelay: Duration = .milliseconds(150),
        browsingMode: BrowserBrowsingMode = .standard,
        linkPreferences: BrowserLinkPreferenceStore = .shared
    ) {
        self.init(
            session: session,
            selection: selection,
            persistence: persistence,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            syncCoalescingDelay: syncCoalescingDelay,
            browsingMode: browsingMode,
            family: BrowserStoreFamily(session: session, browsingMode: browsingMode),
            linkPreferences: linkPreferences
        )
    }

    /// `selection` is what this window shows; without one it opens the launch
    /// Space on its fallback tab.
    init(
        session: BrowserSession,
        selection: BrowserStoreSelection? = nil,
        persistence: any BrowserSessionPersisting,
        credentialVault: any CredentialVault,
        syncCoordinator: BrowserSyncCoordinator?,
        syncCoalescingDelay: Duration,
        browsingMode: BrowserBrowsingMode,
        family: BrowserStoreFamily,
        cloudSyncChangeHandler: (@Sendable () -> Void)? = nil,
        linkPreferences: BrowserLinkPreferenceStore = .shared
    ) {
        let initial = selection ?? BrowserStoreSelection(launching: session)
        self.selection = initial
        self.linkPreferences = linkPreferences
        tabSelectionHistory = BrowserTabSelectionHistory(session: session, selection: initial)
        self.persistence = persistence
        self.credentialVault = credentialVault
        self.syncCoordinator = syncCoordinator
        self.syncCoalescingDelay = syncCoalescingDelay
        self.browsingMode = browsingMode
        self.family = family
        self.cloudSyncChangeHandler = cloudSyncChangeHandler
        localSyncErrorDescription = nil
        family.register(self)
        self.selection.reconcile(using: family.currentSession, excluding: family.deletingSpaceIDs)
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
        do { try family.save(session, to: persistence) }
        catch { localSyncErrorDescription = String(describing: error) }
    }

    func makeWindowStore(
        restoring savedState: BrowserWindowState? = nil,
        restoresTabSelection: Bool = true,
        selectingSpaceID: SpaceID? = nil
    ) -> BrowserStore {
        let windowSession = family.currentSession
        var windowSelection: BrowserStoreSelection
        if var savedState {
            savedState.repair(using: windowSession)
            windowSelection = savedState.selection
        } else {
            windowSelection = BrowserStoreSelection(launching: windowSession, excluding: deletingSpaceIDs)
        }
        if !restoresTabSelection {
            windowSelection = BrowserStoreSelection(selectedSpaceID: windowSelection.selectedSpaceID)
        }
        // Choosing the window's Space keeps whatever tab it restored there,
        // including none.
        if let selectingSpaceID, windowSession.space(id: selectingSpaceID) != nil {
            windowSelection = BrowserStoreSelection(
                selectedSpaceID: selectingSpaceID, selectedTabIDsBySpace: windowSelection.tabSelections)
        }
        let store = BrowserStore(
            session: windowSession,
            selection: windowSelection,
            persistence: persistence,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            syncCoalescingDelay: syncCoalescingDelay,
            browsingMode: browsingMode,
            family: family,
            cloudSyncChangeHandler: cloudSyncChangeHandler,
            linkPreferences: linkPreferences
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
        _ = try syncCoordinator.merge(remoteRecords: records, into: session, storeRevision: revision) { next, journal, journalPersistence, transaction in
            try self.family.installSyncedSession(next, journal: journal, journalPersistence: journalPersistence, transaction: transaction, from: self)
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
        _ = try syncCoordinator.replaceLocalWithCloud(remoteRecords, replacing: session, storeRevision: revision) { next, journal, journalPersistence, transaction in
            try self.family.installSyncedSession(next, journal: journal, journalPersistence: journalPersistence, transaction: transaction, from: self)
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

    func flushPendingSyncPersistence() async {
        await persistence.flushPendingSaves()
        await syncStageTask?.value
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

    /// Stores the shared session and stages sync after a model mutation.
    ///
    /// `scope` is what the mutation changed. It reaches storage only: the
    /// published session, the staged sync records, and the coalescing window are
    /// the same whatever the scope says, because sync stages the in-memory
    /// session rather than anything that was stored. A caller that cannot say
    /// what it changed leaves the scope alone and rewrites everything.
    func persist(
        deletionReason: BrowserSyncTombstoneReason = .superseded,
        syncUrgency: BrowserStoreSyncStageUrgency = .immediate,
        scope: BrowserSessionSaveScope = .everything
    ) {
        let storeRevision = family.publish(session, from: self)
        syncCoordinator?.advanceStoreRevision(to: storeRevision)
        do { try family.save(session, to: persistence, scope: scope) }
        catch { localSyncErrorDescription = String(describing: error); return }
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

    /// `hint` is the core's follow-up selection when this window issued the
    /// accepted command; other windows keep their own selection.
    func receiveFamilySessionChange(
        from previous: BrowserSession, to shared: BrowserSession, hint: BrowserSelectionHint
    ) {
        let previousSelection = selection
        let previousSpace = previous.space(id: previousSelection.selectedSpaceID)
        selection.apply(hint)
        selection.reconcile(using: shared, excluding: deletingSpaceIDs)
        let selectedSpace = shared.space(id: selection.selectedSpaceID)
        if previousSelection.selectedSpaceID != selection.selectedSpaceID
            || previousSpace?.profile.id != selectedSpace?.profile.id
            || previousSpace?.accessPolicy != selectedSpace?.accessPolicy
        {
            tabMultiSelection.clear()
        }
        if let activation = pendingMovedTabActivation,
            selection.selectedSpaceID != activation.spaceID
                || selection.selectedTabID(in: activation.spaceID) != activation.tabID
                || selectedSpace?.profile.id != activation.profileID
        {
            pendingMovedTabActivation = nil
        }
        sessionRevision &+= 1
        tabSelectionHistory.reconcile(session: session, selection: selection)
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
            try mergeRemoteSyncRecords(records)
            await persistence.flushPendingSaves()
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
