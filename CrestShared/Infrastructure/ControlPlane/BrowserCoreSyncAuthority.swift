import CrestCoreABI
import Foundation
import OSLog

/// A cached read of the session's core-owned sync component. The core stages
/// the session's accepted edits itself; this reads the journal it accepted
/// and runs the transactions the transport asks for. Nothing reads the
/// journal until the transport first asks for it, so a launch never decodes
/// it; the counts settings show come from the core's `SyncJournalChanged`.
final class BrowserCoreSyncAuthority: @unchecked Sendable {
    let handle: UInt64
    private let lock = NSLock()
    /// The journal as last read; nil until the first read.
    private var projection: BrowserSyncJournal?
    /// The core's journal version `projection` was read at.
    private var projectedVersion: UInt64

    /// The journal the core accepted last, read on first use. A stage the
    /// core ran since the last read is read again first. A journal this build
    /// cannot read keeps the last one it could, or none.
    var journal: BrowserSyncJournal {
        let current = version
        return lock.withLock {
            if projection == nil || current != projectedVersion {
                do {
                    projection = try Self.read(handle)
                    projectedVersion = current
                } catch {
                    Logger(subsystem: "com.pauldavis.crest", category: "Sync")
                        .error("The sync journal could not be read: \(String(describing: error), privacy: .public)")
                }
            }
            return projection ?? BrowserSyncJournal()
        }
    }

    /// Counts the journals the core accepted.
    fileprivate var version: UInt64 {
        var value: UInt64 = 0
        precondition(crest_sync_authority_version(handle, &value) == CREST_OK)
        return value
    }

    init(journal: BrowserSyncJournal) throws {
        let source = try BrowserCoreSyncJournal(data: journal.encodedSnapshot(), preferences: journal.preferences)
        var handle: UInt64 = 0
        let result = crest_sync_authority_create(source.handle, &handle)
        guard result == CREST_OK else { throw CoreError.rejected(result) }
        self.handle = handle
        projection = journal
        projectedVersion = 0
    }

    /// Takes over an authority the core created, whose journal is read the
    /// first time it is asked for. The caller hands over ownership of the
    /// handle.
    init(adopting handle: UInt64) throws {
        self.handle = handle
        var version: UInt64 = 0
        guard crest_sync_authority_version(handle, &version) == CREST_OK else {
            crest_sync_authority_release(handle)
            throw CoreError.rejected(CREST_INVALID_HANDLE)
        }
        projection = nil
        projectedVersion = version
    }
    deinit { crest_sync_authority_release(handle) }

    private static func read(_ handle: UInt64) throws -> BrowserSyncJournal {
        var snapshot: UInt64 = 0
        let result = crest_sync_authority_snapshot(handle, &snapshot)
        guard result == CREST_OK else { throw CoreError.rejected(result) }
        return try BrowserSyncJournal.acceptingCoreSnapshot(BrowserCoreSyncJournal(adopting: snapshot))
    }

    /// Returns once every stage the core queued before the call has committed
    /// or failed. It blocks, so callers run it off the main actor.
    func flush() {
        precondition(crest_sync_authority_flush(handle) == CREST_OK)
    }

    /// Prepares one journal mutation or session materialization: `request` is a
    /// `BrowserCoreSync.Mutation`, or a `BrowserCoreSync.Request` carrying a
    /// `SessionPreparation`. The core waits for a stage in progress first.
    func prepare<Request: Encodable>(
        _ request: Request, session: BrowserSession? = nil
    ) throws -> BrowserCoreSyncTransaction {
        let data = try JSONEncoder().encode(request)
        guard data.count <= 64 * 1024 * 1024 else { throw CoreError.tooLarge }
        var transaction: UInt64 = 0
        var journalHandle: UInt64 = 0
        var query: UInt64 = 0
        let result = data.withUnsafeBytes {
            crest_sync_authority_prepare(
                handle, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &transaction, &journalHandle, &query)
        }
        guard result == CREST_OK else {
            if query != 0 { let _: Bool = try BrowserCoreSync.readQuery(query) }
            if result == CREST_INVALID_STATE { throw BrowserSyncError.logicalClockExhausted }
            throw CoreError.rejected(result)
        }
        let value = BrowserCoreSyncTransaction(handle: transaction, owner: self)
        let snapshot = BrowserCoreSyncJournal(handle: journalHandle, preferences: journal.preferences)
        // The query is consumed even if decoding the journal fails.
        var materialized: BrowserSession?
        if query != 0 {
            guard let session else {
                crest_sync_query_release(query)
                throw CoreError.rejected(CREST_INVALID_ARGUMENT)
            }
            materialized = try BrowserCoreSync.consumeMaterializedSession(query, from: session)
        }
        let next = try BrowserSyncJournal.acceptingCoreSnapshot(snapshot)
        guard next.deviceID == journal.deviceID else { throw CoreError.rejected(CREST_INVALID_MESSAGE) }
        value.journal = next
        value.session = materialized
        return value
    }
    /// Keeps the journal a transaction published as the core's `version`
    /// of it. A later stage changes the version, so the next read reads again.
    fileprivate func publish(_ journal: BrowserSyncJournal, as version: UInt64) {
        lock.withLock {
            projection = journal
            projectedVersion = version
        }
    }
    enum CoreError: Error {
        case tooLarge
        case rejected(Int32)
        /// The core could not save the journal.
        case storageFailed
    }
}

final class BrowserCoreSyncTransaction {
    let handle: UInt64
    private let owner: BrowserCoreSyncAuthority
    fileprivate(set) var journal: BrowserSyncJournal!
    fileprivate(set) var session: BrowserSession?
    fileprivate init(handle: UInt64, owner: BrowserCoreSyncAuthority) {
        self.handle = handle
        self.owner = owner
    }
    deinit { crest_sync_transaction_release(handle) }
    func seal() throws -> Bool {
        var accepted: Int32 = 0
        let result = crest_sync_transaction_seal(handle, &accepted)
        guard result == CREST_OK else { throw BrowserCoreSyncAuthority.CoreError.rejected(result) }
        return accepted != 0
    }
    /// Publishes the journal. When its session keeps a file the core saves the
    /// journal first; a failed save leaves the transaction unpublished.
    func commit() throws {
        var version: UInt64 = 0
        let result = crest_sync_transaction_commit(handle, &version)
        guard result == CREST_OK else {
            throw result == CREST_STORAGE_FAILED
                ? BrowserCoreSyncAuthority.CoreError.storageFailed : BrowserCoreSyncAuthority.CoreError.rejected(result)
        }
        owner.publish(journal, as: version)
    }
}
