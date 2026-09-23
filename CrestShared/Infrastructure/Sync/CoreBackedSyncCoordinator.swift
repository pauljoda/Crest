import Foundation

/// Schedules platform work for the core session's sync component. This adapter
/// neither orders browser revisions nor accepts journal mutations itself.
final class BrowserSyncCoordinator: @unchecked Sendable {
    private enum CommandError: Error { case superseded }
    typealias Installation = (
        BrowserSession, BrowserSyncJournal, any BrowserSyncJournalPersisting, BrowserCoreSyncTransaction
    ) throws -> Void
    let core: BrowserCoreSyncAuthority
    let status: BrowserSyncCoordinatorStatus
    private let persistence: any BrowserSyncJournalPersisting
    private let mutationLock = NSLock()
    var journal: BrowserSyncJournal { core.journal }

    init(
        persistence: any BrowserSyncJournalPersisting, deviceID: UUID = UUID(),
        preferences: BrowserSyncPreferences = .default
    ) {
        self.persistence = persistence
        let restored: BrowserSyncJournal
        do {
            restored = try persistence.load() ?? BrowserSyncJournal(deviceID: deviceID, preferences: preferences)
            status = .ready
        } catch {
            restored = BrowserSyncJournal(deviceID: deviceID, preferences: preferences)
            status = .recoveredCorruptLocalJournal
        }
        do { core = try BrowserCoreSyncAuthority(journal: restored) } catch {
            preconditionFailure("Cannot initialize core sync: \(error)")
        }
    }

    func advanceStoreRevision(to revision: BrowserStoreSyncRevision) { core.advance(to: revision) }

    @discardableResult
    func stage(
        session: BrowserSession, deletionReason: BrowserSyncTombstoneReason = .superseded,
        at date: Date = .now, storeRevision: BrowserStoreSyncRevision? = nil
    ) throws -> Bool {
        try mutationLock.withLock {
            try commit(
                BrowserCoreSync.Mutation(
                    operation: .stage,
                    arguments: BrowserCoreSync.StageArguments(
                        session: session, deletionReason: deletionReason, at: date)),
                revision: storeRevision) != nil
        }
    }

    func stageInBackground(
        session: BrowserSession, deletionReason: BrowserSyncTombstoneReason = .superseded,
        at date: Date = .now, storeRevision: BrowserStoreSyncRevision? = nil
    ) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            try self.stage(session: session, deletionReason: deletionReason, at: date, storeRevision: storeRevision)
        }.value
    }

    /// A semantic command has already prepared this session. Stage its journal
    /// under the same mutation lock and let the owner commit both durably.
    func installLocalCommand(
        _ session: BrowserSession, deletionReason: BrowserSyncTombstoneReason,
        at date: Date, revision: BrowserStoreSyncRevision, install: Installation
    ) throws {
        try mutationLock.withLock {
            let request = BrowserCoreSync.Mutation(
                operation: .stage,
                arguments: BrowserCoreSync.StageArguments(session: session, deletionReason: deletionReason, at: date))
            guard let transaction = try core.prepare(request, revision: revision), try transaction.seal() else {
                throw CommandError.superseded
            }
            try install(session, transaction.journal, persistence, transaction)
            transaction.publish()
        }
    }

    func merge(
        remoteRecords: [BrowserSyncRecord], into localSession: BrowserSession, at date: Date = .now,
        storeRevision: BrowserStoreSyncRevision? = nil, install: Installation? = nil
    ) throws -> BrowserSession {
        try prepareSession(
            localSession, records: remoteRecords, replacing: false, at: date, revision: storeRevision,
            install: install)
    }

    func replaceLocalWithCloud(
        _ remoteRecords: [BrowserSyncRecord], replacing localSession: BrowserSession,
        at date: Date = .now, storeRevision: BrowserStoreSyncRevision? = nil, install: Installation? = nil
    ) throws -> BrowserSession {
        try prepareSession(
            localSession, records: remoteRecords, replacing: true, at: date, revision: storeRevision, install: install)
    }

    private func prepareSession(
        _ session: BrowserSession, records: [BrowserSyncRecord], replacing: Bool,
        at date: Date, revision: BrowserStoreSyncRevision?, install: Installation?
    ) throws -> BrowserSession {
        try mutationLock.withLock {
            // Validate the decoded transport boundary before entering the core.
            try journal.validateIncoming(records, checksSpace: !replacing)
            let emptySpace: BrowserSpace? =
                if replacing && records.isEmpty {
                    Self.blankSpace()
                } else if session.spaces.isEmpty {
                    BrowserSession.makeBlankSpace(number: 1)
                } else {
                    nil
                }
            let preparation = BrowserCoreSync.SessionPreparation(
                session: BrowserCoreSessionAuthority.compact(session), records: records,
                now: date.timeIntervalSinceReferenceDate, emptySpace: emptySpace)
            let request = BrowserCoreSync.Request(operation: replacing ? .replace : .merge, arguments: preparation)
            return try commit(request, revision: revision, session: session, install: install)?.session ?? session
        }
    }

    func prepareToOverwriteCloud(
        with session: BrowserSession, remoteRecords: [BrowserSyncRecord],
        at date: Date = .now, storeRevision: BrowserStoreSyncRevision? = nil
    ) throws {
        try mutationLock.withLock {
            try journal.validateIncoming(remoteRecords, checksSpace: false)
            _ = try commit(
                BrowserCoreSync.Mutation(
                    operation: .overwrite,
                    arguments: BrowserCoreSync.OverwriteArguments(session: session, records: remoteRecords, at: date)),
                revision: storeRevision)
        }
    }

    func markUploaded(_ recordIDs: Set<BrowserSyncRecordID>) throws {
        try acknowledge(BrowserCoreSync.AcknowledgementArguments(recordIDs))
    }

    func markUploaded(_ acknowledgedVersions: [BrowserSyncRecordID: BrowserSyncVersion]) throws {
        try acknowledge(BrowserCoreSync.AcknowledgementArguments(acknowledgedVersions))
    }

    private func acknowledge(_ arguments: BrowserCoreSync.AcknowledgementArguments) throws {
        try mutationLock.withLock {
            _ = try commit(BrowserCoreSync.Mutation(operation: .acknowledge, arguments: arguments), revision: nil)
        }
    }

    private func commit<Request: Encodable>(
        _ request: Request, revision: BrowserStoreSyncRevision?,
        session: BrowserSession? = nil, install: Installation? = nil
    ) throws -> BrowserCoreSyncTransaction? {
        guard let transaction = try core.prepare(request, revision: revision, session: session),
            try transaction.seal()
        else { return nil }
        if let install, let next = transaction.session {
            try install(next, transaction.journal, persistence, transaction)
        } else {
            try persistence.save(transaction.journal)
        }
        transaction.publish()
        return transaction
    }

    private static func blankSpace() -> BrowserSpace {
        let tab = BrowserTab.startPage()
        return BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Space 1",
            symbol: "square.grid.2x2.fill", accent: .indigo, folders: [], tabs: [tab])
    }
}
