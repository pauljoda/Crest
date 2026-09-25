import CrestCoreABI
import Foundation
import OSLog

/// A cached read of the session's core-owned sync component. The core stages
/// the session's accepted edits itself; this reads the journal it accepted
/// and runs the transactions the transport asks for. Nothing reads the
/// journal until the transport first asks for it, so a launch never decodes
/// it; the counts settings show come from the core's `SyncJournalChanged`.
///
/// A journal this build cannot read pauses the transport: every read throws
/// `BrowserSyncError.unreadableJournal` and nothing stands in for it, neither
/// an empty journal nor an earlier one. The next journal the core accepts is
/// read again.
final class BrowserCoreSyncAuthority: @unchecked Sendable {
    let handle: UInt64
    private let lock = NSLock()
    /// The journal as last read; nil until the first read and while the
    /// journal cannot be read.
    private var projection: BrowserSyncJournal?
    /// The core's journal version `projection` was read at.
    private var projectedVersion: UInt64
    /// The version the last read failed at and why; nil once a read succeeds.
    private var unreadable: (version: UInt64, error: BrowserSyncError)?

    /// The journal the core accepted last, read on first use and again after
    /// each journal the core accepts. Throws `BrowserSyncError.unreadableJournal`
    /// when this build cannot read it, without reading a journal it already
    /// failed to read again.
    func journal() throws -> BrowserSyncJournal {
        let current = version
        return try lock.withLock {
            if let projection, projectedVersion == current { return projection }
            if let unreadable, unreadable.version == current { throw unreadable.error }
            do {
                let read = try Self.read(handle)
                projection = read
                projectedVersion = current
                unreadable = nil
                return read
            } catch {
                let reason = Self.reason(error)
                let failure = BrowserSyncError.unreadableJournal(reason)
                projection = nil
                unreadable = (current, failure)
                Logger(subsystem: "com.pauldavis.crest", category: "Sync")
                    .error("The sync journal could not be read, so sync is paused: \(reason, privacy: .public)")
                throw failure
            }
        }
    }

    /// Throws the failure that paused the transport, until the core accepts a
    /// journal this build can read. A journal that changed since the failure
    /// is read again, so this blocks; while nothing failed it reads nothing.
    func requireReadable() throws {
        guard lock.withLock({ unreadable != nil }) else { return }
        _ = try journal()
    }

    /// Why a journal could not be read, naming a record or a field but never
    /// what a record holds.
    private static func reason(_ error: any Error) -> String {
        switch error {
        case BrowserSyncError.invalidURL:
            return "a record holds an address sync does not carry"
        case let error as BrowserSyncError:
            return String(describing: error)
        case let error as DecodingError:
            let context: DecodingError.Context
            switch error {
            case .typeMismatch(_, let found), .valueNotFound(_, let found), .keyNotFound(_, let found),
                .dataCorrupted(let found):
                context = found
            @unknown default:
                return "a value does not decode"
            }
            let path = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }
            return "a value does not decode at \(path.joined(separator: "."))"
        default:
            return String(describing: type(of: error))
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
    /// Throws `BrowserSyncError.unreadableJournal`, and prepares nothing, while
    /// the journal cannot be read.
    func prepare<Request: Encodable>(
        _ request: Request, session: BrowserSession? = nil
    ) throws -> BrowserCoreSyncTransaction {
        let current = try journal()
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
        let snapshot = BrowserCoreSyncJournal(handle: journalHandle, preferences: current.preferences)
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
        guard next.deviceID == current.deviceID else { throw CoreError.rejected(CREST_INVALID_MESSAGE) }
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
            unreadable = nil
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
