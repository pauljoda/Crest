#if CREST_CORE_BACKED
import Foundation

/// Schedules platform work for the core session's sync component. This adapter
/// neither orders browser revisions nor accepts journal mutations itself.
final class BrowserSyncCoordinator: @unchecked Sendable {
    typealias Installation = (BrowserSession, BrowserSyncJournal, any BrowserSyncJournalPersisting, BrowserCoreSyncTransaction) throws -> Void
    let core: BrowserCoreSyncAuthority
    let status: BrowserSyncCoordinatorStatus
    private let persistence: any BrowserSyncJournalPersisting
    private let mutationLock = NSLock()
    var journal: BrowserSyncJournal { core.journal }

    init(persistence: any BrowserSyncJournalPersisting, deviceID: UUID = UUID(), preferences: BrowserSyncPreferences = .default) {
        self.persistence = persistence
        let restored: BrowserSyncJournal
        do { restored = try persistence.load() ?? BrowserSyncJournal(deviceID: deviceID, preferences: preferences); status = .ready }
        catch { restored = BrowserSyncJournal(deviceID: deviceID, preferences: preferences); status = .recoveredCorruptLocalJournal }
        do { core = try BrowserCoreSyncAuthority(journal: restored) }
        catch { preconditionFailure("Cannot initialize core sync: \(error)") }
    }

    func advanceStoreRevision(to revision: BrowserStoreSyncRevision) { core.advance(to: revision) }

    @discardableResult
    func stage(session: BrowserSession, deletionReason: BrowserSyncTombstoneReason = .superseded,
        at date: Date = .now, storeRevision: BrowserStoreSyncRevision? = nil) throws -> Bool {
        try mutationLock.withLock {
            try commit([
                "version": 1, "operation": "stage", "arguments": [
                    "session": try value(session), "deletionReason": deletionReason.rawValue,
                    "now": date.timeIntervalSinceReferenceDate
                ]
            ], revision: storeRevision) != nil
        }
    }
    func stageInBackground(session: BrowserSession, deletionReason: BrowserSyncTombstoneReason = .superseded,
        at date: Date = .now, storeRevision: BrowserStoreSyncRevision? = nil) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            try self.stage(session: session, deletionReason: deletionReason, at: date, storeRevision: storeRevision)
        }.value
    }

    func merge(remoteRecords: [BrowserSyncRecord], into localSession: BrowserSession, at date: Date = .now,
        storeRevision: BrowserStoreSyncRevision? = nil, install: Installation? = nil) throws -> BrowserSession {
        try prepareSession(localSession, records: remoteRecords, replacing: false, at: date, revision: storeRevision, install: install)
    }
    func replaceLocalWithCloud(_ remoteRecords: [BrowserSyncRecord], replacing localSession: BrowserSession,
        at date: Date = .now, storeRevision: BrowserStoreSyncRevision? = nil, install: Installation? = nil) throws -> BrowserSession {
        try prepareSession(localSession, records: remoteRecords, replacing: true, at: date, revision: storeRevision, install: install)
    }
    private func prepareSession(_ session: BrowserSession, records: [BrowserSyncRecord], replacing: Bool,
        at date: Date, revision: BrowserStoreSyncRevision?, install: Installation?) throws -> BrowserSession {
        try mutationLock.withLock {
            // Validate the decoded transport boundary before entering the core.
            try journal.validateIncoming(records, checksSpace: !replacing)
            var request: [String: Any] = [
                "version": 1, "operation": replacing ? "replace" : "merge", "session": try value(session),
                "records": try BrowserCoreSync.value(records), "now": date.timeIntervalSinceReferenceDate
            ]
            if replacing && records.isEmpty {
                request["emptySpace"] = try BrowserCoreSync.value(Self.blankSpace())
            } else if session.spaces.isEmpty {
                request["emptySpace"] = try BrowserCoreSync.value(BrowserSession.makeBlankSpace(number: 1))
            }
            return try commit(request, revision: revision, session: session, install: install)?.session ?? session
        }
    }
    func prepareToOverwriteCloud(with session: BrowserSession, remoteRecords: [BrowserSyncRecord],
        at date: Date = .now, storeRevision: BrowserStoreSyncRevision? = nil) throws {
        try mutationLock.withLock {
            try journal.validateIncoming(remoteRecords, checksSpace: false)
            _ = try commit(["version": 1, "operation": "overwrite", "arguments": [
                "session": try value(session), "records": try BrowserCoreSync.value(remoteRecords),
                "now": date.timeIntervalSinceReferenceDate
            ]], revision: storeRevision)
        }
    }
    func markUploaded(_ recordIDs: Set<BrowserSyncRecordID>) throws {
        try acknowledge(recordIDs.map { ["id": try BrowserCoreSync.value($0)] })
    }
    func markUploaded(_ acknowledgedVersions: [BrowserSyncRecordID: BrowserSyncVersion]) throws {
        try acknowledge(acknowledgedVersions.map {
            ["id": try BrowserCoreSync.value($0.key), "version": try BrowserCoreSync.value($0.value)]
        })
    }
    private func acknowledge(_ values: [[String: Any]]) throws {
        try mutationLock.withLock {
            _ = try commit(["version": 1, "operation": "acknowledge", "arguments": ["acknowledgements": values]], revision: nil)
        }
    }

    private func commit(_ request: [String: Any], revision: BrowserStoreSyncRevision?,
        session: BrowserSession? = nil, install: Installation? = nil) throws -> BrowserCoreSyncTransaction? {
        guard let transaction = try core.prepare(request, revision: revision, session: session),
            try transaction.seal() else { return nil }
        if let install, let next = transaction.session {
            try install(next, transaction.journal, persistence, transaction)
        } else { try persistence.save(transaction.journal) }
        transaction.publish()
        return transaction
    }
    private func value(_ session: BrowserSession) throws -> Any {
        try BrowserCoreSync.value(BrowserCoreSessionAuthority.compact(session))
    }
    private static func blankSpace() -> BrowserSpace {
        let tab = BrowserTab.startPage()
        return BrowserSpace(id: SpaceID(), profile: BrowsingProfile(), name: "Space 1",
            symbol: "square.grid.2x2.fill", accent: .indigo, folders: [], tabs: [tab], selectedTabID: tab.id)
    }
}
#endif
