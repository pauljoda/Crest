import Foundation

#if !CREST_CORE_BACKED

final class BrowserSyncCoordinator: @unchecked Sendable {
    /// Readers and main-actor revision updates only touch committed state.
    /// Projection and encoding serialize separately so a background save cannot
    /// make the next browsing interaction wait for the whole journal to encode.
    private let stateLock = NSLock()
    private let mutationLock = NSLock()
    private var storedJournal: BrowserSyncJournal
    private var storedLatestStoreRevision: BrowserStoreSyncRevision?
    let status: BrowserSyncCoordinatorStatus
    private let persistence: any BrowserSyncJournalPersisting

    var journal: BrowserSyncJournal {
        stateLock.withLock { storedJournal }
    }

    init(
        persistence: any BrowserSyncJournalPersisting,
        deviceID: UUID = UUID(),
        preferences: BrowserSyncPreferences = .default
    ) {
        self.persistence = persistence
        do {
            storedJournal =
                try persistence.load()
                ?? BrowserSyncJournal(deviceID: deviceID, preferences: preferences)
            status = .ready
        } catch {
            storedJournal = BrowserSyncJournal(deviceID: deviceID, preferences: preferences)
            status = .recoveredCorruptLocalJournal
        }
    }

    /// Publishes the newest main-actor session revision before its background
    /// projection begins. This closes the narrow window where an already-running
    /// task from another window could snapshot the journal after a newer
    /// session existed but before that newer task reached the coordinator.
    func advanceStoreRevision(to revision: BrowserStoreSyncRevision) {
        stateLock.withLock {
            guard storedLatestStoreRevision.map({ $0 < revision }) ?? true else {
                return
            }
            storedLatestStoreRevision = revision
        }
    }

    @discardableResult
    func stage(
        session: BrowserSession,
        deletionReason: BrowserSyncTombstoneReason = .superseded,
        at date: Date = .now,
        storeRevision: BrowserStoreSyncRevision? = nil
    ) throws -> Bool {
        try commit(
            storeRevision: storeRevision,
            staleResult: false
        ) { journal in
            try journal.stage(
                session: session,
                deletionReason: deletionReason,
                at: date
            )
            return true
        }
    }

    func stageInBackground(
        session: BrowserSession,
        deletionReason: BrowserSyncTombstoneReason = .superseded,
        at date: Date = .now,
        storeRevision: BrowserStoreSyncRevision? = nil
    ) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            try self.stage(
                session: session,
                deletionReason: deletionReason,
                at: date,
                storeRevision: storeRevision
            )
        }.value
    }

    func merge(
        remoteRecords: [BrowserSyncRecord],
        into localSession: BrowserSession,
        at date: Date = .now,
        storeRevision: BrowserStoreSyncRevision? = nil,
        install: ((BrowserSession, BrowserSyncJournal, any BrowserSyncJournalPersisting) throws -> Void)? = nil
    ) throws -> BrowserSession {
        try commit(
            storeRevision: storeRevision,
            staleResult: localSession,
            persist: install.map { install in { result, journal in try install(result, journal, self.persistence) } }
        ) { journal in
            // Incoming batches can arrive before a coalesced local edit stages.
            // Preserve that edit in the same transaction before materialization.
            if !localSession.hasDisposableSeedState {
                try journal.stage(session: localSession, deletionReason: .superseded, at: date)
            }
            try journal.merge(remoteRecords)
            var materialized = try journal.materializedSession(applyingTo: localSession)
            let removedRecords = materialized.applyDataRetentionPolicies(now: date)
            try journal.stage(
                session: materialized,
                deletionReason: removedRecords ? .retention : .superseded,
                at: date
            )
            return materialized
        }
    }

    func prepareToOverwriteCloud(
        with session: BrowserSession,
        remoteRecords: [BrowserSyncRecord],
        at date: Date = .now,
        storeRevision: BrowserStoreSyncRevision? = nil
    ) throws {
        try commit(
            storeRevision: storeRevision,
            staleResult: ()
        ) { journal in
            try journal.prepareToOverwriteCloud(
                with: session,
                remoteRecords: remoteRecords,
                at: date
            )
        }
    }

    func replaceLocalWithCloud(
        _ remoteRecords: [BrowserSyncRecord],
        replacing localSession: BrowserSession,
        at date: Date = .now,
        storeRevision: BrowserStoreSyncRevision? = nil,
        install: ((BrowserSession, BrowserSyncJournal, any BrowserSyncJournalPersisting) throws -> Void)? = nil
    ) throws -> BrowserSession {
        try commit(
            storeRevision: storeRevision,
            staleResult: localSession,
            persist: install.map { install in { result, journal in try install(result, journal, self.persistence) } }
        ) { journal in
            try journal.replaceWithCloud(remoteRecords)
            var materialized =
                if remoteRecords.isEmpty {
                    Self.blankSession()
                } else {
                    try journal.materializedSession(applyingTo: localSession)
                }
            let removedRecords = materialized.applyDataRetentionPolicies(now: date)
            if removedRecords {
                try journal.stage(
                    session: materialized,
                    deletionReason: .retention,
                    at: date
                )
            }
            return materialized
        }
    }

    private static func blankSession() -> BrowserSession {
        let tab = BrowserTab.startPage()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Space 1",
            symbol: "square.grid.2x2.fill",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }

    func markUploaded(_ recordIDs: Set<BrowserSyncRecordID>) throws {
        try commit { journal in
            try journal.markUploaded(recordIDs)
        }
    }

    func markUploaded(_ acknowledgedVersions: [BrowserSyncRecordID: BrowserSyncVersion]) throws {
        try commit { journal in
            try journal.markUploaded(acknowledgedVersions)
        }
    }

    private func commit<Result>(
        _ mutation: (inout BrowserSyncJournal) throws -> Result
    ) throws -> Result {
        try mutationLock.withLock {
            var candidate = stateLock.withLock { storedJournal }
            let result = try mutation(&candidate)
            try persistence.save(candidate)
            stateLock.withLock { storedJournal = candidate }
            return result
        }
    }

    private func commit<Result>(
        storeRevision: BrowserStoreSyncRevision?,
        staleResult: @autoclosure () -> Result,
        persist: ((Result, BrowserSyncJournal) throws -> Void)? = nil,
        _ mutation: (inout BrowserSyncJournal) throws -> Result
    ) throws -> Result {
        try mutationLock.withLock {
            guard
                var candidate = stateLock.withLock({
                    isStale(storeRevision) ? nil : storedJournal
                })
            else { return staleResult() }
            let result = try mutation(&candidate)
            guard stateLock.withLock({ !isStale(storeRevision) }) else { return staleResult() }
            if let persist { try persist(result, candidate) }
            else { try persistence.save(candidate) }
            stateLock.withLock {
                storedJournal = candidate
                // A newer session may arrive while this save is encoding.
                // Its stage follows this writer; keep its revision barrier so
                // an older queued snapshot cannot commit in between them.
                if let storeRevision,
                    storedLatestStoreRevision.map({ $0 < storeRevision }) ?? true
                {
                    storedLatestStoreRevision = storeRevision
                }
            }
            return result
        }
    }

    /// Called only while holding the committed-state lock.
    private func isStale(_ revision: BrowserStoreSyncRevision?) -> Bool {
        guard let revision, let latest = storedLatestStoreRevision else { return false }
        return revision < latest
    }
}
#endif
