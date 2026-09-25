import Foundation

/// Runs the cloud transport's journal work against the session's core-owned
/// sync component. The core stages the session's accepted edits itself; this
/// adapter neither orders nor stages them.
final class BrowserSyncCoordinator: @unchecked Sendable {
    let core: BrowserCoreSyncAuthority
    let status: BrowserSyncCoordinatorStatus
    /// Where a memory-only composition keeps a copy of its journal; nil when
    /// the core saves the journal in its session file.
    private let persistence: (any BrowserSyncJournalPersisting)?
    private let mutationLock = NSLock()

    #if DEBUG
        /// The journal, for the journal contract tests, which never hold one
        /// this build cannot read. TRANSITIONAL until slice 8c ports them to
        /// the core.
        var journal: BrowserSyncJournal {
            do { return try core.journal() } catch {
                preconditionFailure("A journal contract test holds a journal it cannot read: \(error)")
            }
        }
    #endif

    /// The journal the core accepted last. Throws
    /// `BrowserSyncError.unreadableJournal` while this build cannot read it,
    /// which pauses the transport.
    func readJournal() throws -> BrowserSyncJournal { try core.journal() }

    /// Throws the failure that paused the transport until the core accepts a
    /// journal this build can read. It may read the journal, so callers run
    /// it off the main actor.
    func requireReadableJournal() throws { try core.requireReadable() }

    /// The sync component of the session the core keeps in its file. The core
    /// saves every journal this component accepts.
    init(core: BrowserCoreSyncAuthority) {
        self.core = core
        persistence = nil
        status = .ready
    }

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

    /// Returns once every stage the core queued before the call has committed
    /// or failed, without waiting out a coalescing delay. A memory-only
    /// composition then keeps a copy of the journal it holds.
    func staged() async {
        await Task.detached(priority: .utility) { [self] in
            core.flush()
            guard let persistence else { return }
            mutationLock.withLock { if let journal = try? readJournal() { try? persistence.save(journal) } }
        }.value
    }

    /// Stages `session` in the journal directly. The core stages the session
    /// it owns by itself; this stages a session no core owns, as the journal
    /// contract tests do.
    @discardableResult
    func stage(
        session: BrowserSession, deletionReason: SyncDeletionReason = .superseded, at date: Date = .now
    ) throws -> Bool {
        try mutationLock.withLock {
            try commit(
                BrowserCoreSync.Mutation(
                    operation: .stage,
                    arguments: BrowserCoreSync.StageArguments(
                        session: session, deletionReason: deletionReason, at: date))) != nil
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
            _ = try commit(BrowserCoreSync.Mutation(operation: .acknowledge, arguments: arguments))
        }
    }

    private func commit<Request: Encodable>(_ request: Request) throws -> BrowserCoreSyncTransaction? {
        let transaction = try core.prepare(request)
        guard try transaction.seal() else { return nil }
        try persistence?.save(transaction.journal)
        try transaction.commit()
        return transaction
    }
}
