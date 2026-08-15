import Foundation

extension BrowserStore {
    func mergeRemoteSyncRecords(_ records: [BrowserSyncRecord]) throws {
        guard let syncCoordinator else { return }
        session = try syncCoordinator.merge(remoteRecords: records, into: session)
        family.publish(session, from: self)
        persistence.save(session)
        localSyncErrorDescription = nil
    }

    func prepareToOverwriteCloud(with remoteRecords: [BrowserSyncRecord]) throws {
        guard let syncCoordinator else { return }
        try syncCoordinator.prepareToOverwriteCloud(
            with: session,
            remoteRecords: remoteRecords
        )
        localSyncErrorDescription = nil
    }

    func replaceLocalWithCloud(_ remoteRecords: [BrowserSyncRecord]) throws {
        guard let syncCoordinator else { return }
        session = try syncCoordinator.replaceLocalWithCloud(
            remoteRecords,
            replacing: session
        )
        family.publish(session, from: self)
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
        family.publish(session, from: self)
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
                try await syncCoordinator.stageInBackground(
                    session: sessionSnapshot,
                    deletionReason: deletionReason
                )
                self?.localSyncErrorDescription = nil
                self?.cloudSyncChangeHandler?()
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
}
