import Foundation
import Observation

@Observable
@MainActor
final class BrowserStore {
    var session: BrowserSession {
        get { selection.applying(to: family.currentSession) }
        set {
            family.replaceSession(newValue, from: self)
        }
    }
    private var selection: BrowserStoreSelection
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
    var selectedSpace: BrowserSpace? {
        guard !deletingSpaceIDs.contains(selection.selectedSpaceID) else {
            return nil
        }
        return selection.selectedSpace(in: family.currentSession)
    }
    var selectedTab: BrowserTab? {
        guard let space = selectedSpace, let tabID = space.selectedTabID else { return nil }
        return space.tabs.first { $0.id == tabID }
    }
    var isPrivateBrowsing: Bool { browsingMode.isPrivate }
    var isTemporaryWorkspace: Bool { temporarySourceAssignment != nil }
    var temporarySourceAssignment: BrowserSpaceRuntimeAssignment? { family.temporarySourceAssignment }
    var pendingSyncRecordCount: Int {
        guard !session.hasDisposableSeedState else { return 0 }
        return syncCoordinator?.journal.pendingRecordIDs.count ?? 0
    }
    var localSyncCoordinatorStatus: BrowserSyncCoordinatorStatus? { syncCoordinator?.status }

    convenience init(
        session: BrowserSession,
        persistence: any BrowserSessionPersisting,
        credentialVault: any CredentialVault = InMemoryCredentialVault(),
        syncCoordinator: BrowserSyncCoordinator? = nil,
        syncCoalescingDelay: Duration = .milliseconds(150),
        browsingMode: BrowserBrowsingMode = .standard,
        linkPreferences: BrowserLinkPreferenceStore = .shared
    ) {
        self.init(
            session: session,
            persistence: persistence,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            syncCoalescingDelay: syncCoalescingDelay,
            browsingMode: browsingMode,
            family: BrowserStoreFamily(session: session),
            linkPreferences: linkPreferences
        )
    }

    init(
        session: BrowserSession,
        persistence: any BrowserSessionPersisting,
        credentialVault: any CredentialVault,
        syncCoordinator: BrowserSyncCoordinator?,
        syncCoalescingDelay: Duration,
        browsingMode: BrowserBrowsingMode,
        family: BrowserStoreFamily,
        cloudSyncChangeHandler: (@Sendable () -> Void)? = nil,
        linkPreferences: BrowserLinkPreferenceStore = .shared
    ) {
        selection = BrowserStoreSelection(session: session)
        self.linkPreferences = linkPreferences
        tabSelectionHistory = BrowserTabSelectionHistory(session: session)
        self.persistence = persistence
        self.credentialVault = credentialVault
        self.syncCoordinator = syncCoordinator
        self.syncCoalescingDelay = syncCoalescingDelay
        self.browsingMode = browsingMode
        self.family = family
        self.cloudSyncChangeHandler = cloudSyncChangeHandler
        localSyncErrorDescription = nil
        family.register(self)
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
        session = .privateBrowsing()
        localSyncErrorDescription = nil
        let revision = family.publish(session, from: self)
        syncCoordinator?.advanceStoreRevision(to: revision)
        persistence.save(session)
    }

    func makeWindowStore(
        restoring savedState: BrowserWindowState? = nil,
        restoresTabSelection: Bool = true,
        selectingSpaceID: SpaceID? = nil
    ) -> BrowserStore {
        var windowSession = family.currentSession
        if var savedState {
            savedState.repair(using: windowSession)
            windowSession.selectedSpaceID = savedState.selectedSpaceID
            for index in windowSession.spaces.indices {
                let spaceID = windowSession.spaces[index].id
                windowSession.spaces[index].selectedTabID = savedState.selectedTabIDsBySpace[spaceID]
            }
        } else {
            windowSession.selectDefaultSpaceForLaunch()
        }
        if let selectingSpaceID, windowSession.space(id: selectingSpaceID) != nil {
            windowSession.selectedSpaceID = selectingSpaceID
        }
        if !restoresTabSelection {
            for index in windowSession.spaces.indices {
                windowSession.spaces[index].selectedTabID = nil
            }
        }
        let store = BrowserStore(
            session: windowSession,
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
        session = try syncCoordinator.merge(
            remoteRecords: records,
            into: session,
            storeRevision: revision
        )
        family.publish(session, from: self, at: revision)
        persistence.save(session)
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
        session = try syncCoordinator.replaceLocalWithCloud(
            remoteRecords,
            replacing: session,
            storeRevision: revision
        )
        family.publish(session, from: self, at: revision)
        persistence.save(session)
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
        persistence.save(session, scope: scope)
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

    func receiveFamilySessionChange(
        from previous: BrowserSession, to shared: BrowserSession, adoptingSelection: Bool
    ) {
        let previousSelection = selection
        let previousSpace = previous.space(id: previousSelection.selectedSpaceID)
        if adoptingSelection {
            selection = BrowserStoreSelection(session: shared)
        } else {
            selection.reconcile(using: shared, excluding: deletingSpaceIDs)
        }
        let selectedSpace = shared.space(id: selection.selectedSpaceID)
        if previousSelection.selectedSpaceID != selection.selectedSpaceID
            || previousSpace?.profile.id != selectedSpace?.profile.id
            || previousSpace?.accessPolicy != selectedSpace?.accessPolicy
        {
            tabMultiSelection.clear()
        }
        if let activation = pendingMovedTabActivation,
            selection.selectedSpaceID != activation.spaceID
                || session.selectedTab?.id != activation.tabID
                || selectedSpace?.profile.id != activation.profileID
        {
            pendingMovedTabActivation = nil
        }
        sessionRevision &+= 1
        tabSelectionHistory.reconcile(session: session)
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
        try syncCoordinator?.markUploaded(acknowledgedVersions)
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

// MARK: - Extension Sessions

extension BrowserStore: BrowserExtensionTabWindowSessionHandling {}
