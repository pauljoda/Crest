import Foundation
import Observation

@Observable
@MainActor
final class BrowserStore {
    var session: BrowserSession {
        didSet {
            sessionRevision &+= 1
            tabSelectionHistory.reconcile(session: session)
        }
    }
    private(set) var sessionRevision = 0
    var localSyncErrorDescription: String?
    let browsingMode: BrowserBrowsingMode
    let tabDragState = BrowserTabDragState()
    let folderDragState = BrowserFolderDragState()
    let sidebarReorderState = BrowserSidebarReorderState()
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

    var deletingSpaceIDs: Set<SpaceID> { family.deletingSpaceIDs }
    var selectedSpace: BrowserSpace? {
        guard !deletingSpaceIDs.contains(session.selectedSpaceID) else {
            return nil
        }
        return session.selectedSpace
    }
    var selectedTab: BrowserTab? {
        guard selectedSpace != nil else { return nil }
        return session.selectedTab
    }
    var isPrivateBrowsing: Bool { browsingMode.isPrivate }
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
        browsingMode: BrowserBrowsingMode = .standard
    ) {
        self.init(
            session: session,
            persistence: persistence,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            syncCoalescingDelay: syncCoalescingDelay,
            browsingMode: browsingMode,
            family: BrowserStoreFamily(session: session)
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
        cloudSyncChangeHandler: (@Sendable () -> Void)? = nil
    ) {
        self.session = session
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
        tabDragState.end()
        folderDragState.end()
        session = .privateBrowsing()
        localSyncErrorDescription = nil
        let revision = family.publish(session, from: self)
        syncCoordinator?.advanceStoreRevision(to: revision)
        persistence.save(session)
    }

    func makeWindowStore(restoring savedState: BrowserWindowState? = nil) -> BrowserStore {
        var windowSession = family.authoritativeSession
        if var savedState {
            savedState.repair(using: windowSession)
            windowSession.selectedSpaceID = savedState.selectedSpaceID
            for index in windowSession.spaces.indices {
                let spaceID = windowSession.spaces[index].id
                guard let tabID = savedState.selectedTabIDsBySpace[spaceID],
                    windowSession.spaces[index].contains(tabID)
                else { continue }
                windowSession.spaces[index].selectedTabID = tabID
            }
        }
        windowSession.selectDefaultSpaceForLaunch()
        windowSession.repairRuntimeIntegrity()
        let store = BrowserStore(
            session: windowSession,
            persistence: persistence,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            syncCoalescingDelay: syncCoalescingDelay,
            browsingMode: browsingMode,
            family: family,
            cloudSyncChangeHandler: cloudSyncChangeHandler
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

    /// Publishes to every window, stores the session, and stages sync.
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

    func receiveSharedSession(_ sharedSession: BrowserSession) {
        let selectedSpaceID = session.selectedSpaceID
        let selectedTabIDs: [SpaceID: TabID] = Dictionary(
            uniqueKeysWithValues: session.spaces.compactMap { space in
                guard let tabID = space.selectedTabID else { return nil }
                return (space.id, tabID)
            }
        )
        session = sharedSession
        if session.space(id: selectedSpaceID) != nil,
            !deletingSpaceIDs.contains(selectedSpaceID)
        {
            session.selectedSpaceID = selectedSpaceID
        }
        for index in session.spaces.indices {
            let spaceID = session.spaces[index].id
            guard let tabID = selectedTabIDs[spaceID],
                session.spaces[index].contains(tabID)
            else { continue }
            session.spaces[index].selectedTabID = tabID
        }
        session.repairRuntimeIntegrity()
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
        try mergeRemoteSyncRecords(records)
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
