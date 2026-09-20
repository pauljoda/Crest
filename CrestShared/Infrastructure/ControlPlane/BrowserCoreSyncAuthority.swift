#if CREST_CORE_BACKED
import CrestCoreABI
import Foundation

/// Native scheduling and a cached read projection of the session's core-owned
/// sync component. Revision and publication decisions happen in the core.
final class BrowserCoreSyncAuthority: @unchecked Sendable {
    let handle: UInt64
    private let lock = NSLock()
    private var projection: BrowserSyncJournal
    var journal: BrowserSyncJournal { lock.withLock { projection } }

    init(journal: BrowserSyncJournal) throws {
        let source = try BrowserCoreSyncJournal(data: journal.encodedSnapshot(), preferences: journal.preferences)
        var handle: UInt64 = 0
        let result = crest_sync_authority_create(source.handle, &handle)
        guard result == CREST_OK else { throw CoreError.rejected(result) }
        self.handle = handle
        projection = journal
    }
    deinit { crest_sync_authority_release(handle) }

    func advance(to revision: BrowserStoreSyncRevision) {
        precondition(crest_sync_authority_advance(handle, revision.value) == CREST_OK)
    }
    func prepare(_ request: [String: Any], revision: BrowserStoreSyncRevision?,
        session: BrowserSession? = nil) throws -> BrowserCoreSyncTransaction? {
        let data = try JSONSerialization.data(withJSONObject: request)
        guard data.count <= 64 * 1024 * 1024 else { throw CoreError.tooLarge }
        var transaction: UInt64 = 0, journalHandle: UInt64 = 0, query: UInt64 = 0
        let result = data.withUnsafeBytes {
            crest_sync_authority_prepare(handle, revision == nil ? 0 : 1, revision?.value ?? 0,
                $0.bindMemory(to: UInt8.self).baseAddress, data.count, &transaction, &journalHandle, &query)
        }
        guard result == CREST_OK else {
            if query != 0 { let _: Bool = try BrowserCoreSync.readQuery(query) }
            if result == CREST_INVALID_STATE { throw BrowserSyncError.logicalClockExhausted }
            throw CoreError.rejected(result)
        }
        guard transaction != 0 else { return nil }
        let value = BrowserCoreSyncTransaction(handle: transaction, owner: self)
        let snapshot = BrowserCoreSyncJournal(handle: journalHandle, preferences: journal.preferences)
        // The query is consumed even if decoding the journal fails.
        var materialized: BrowserSession?
        if query != 0 {
            guard let session else { crest_sync_query_release(query); throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
            materialized = try BrowserCoreSync.consumeMaterializedSession(query, from: session)
        }
        let next = try BrowserSyncJournal.acceptingCoreSnapshot(snapshot)
        guard next.deviceID == journal.deviceID else { throw CoreError.rejected(CREST_INVALID_MESSAGE) }
        value.journal = next
        value.session = materialized
        return value
    }
    fileprivate func publish(_ journal: BrowserSyncJournal) { lock.withLock { projection = journal } }
    enum CoreError: Error { case tooLarge, rejected(Int32) }
}

final class BrowserCoreSyncTransaction {
    let handle: UInt64
    private let owner: BrowserCoreSyncAuthority
    fileprivate(set) var journal: BrowserSyncJournal!
    fileprivate(set) var session: BrowserSession?
    fileprivate init(handle: UInt64, owner: BrowserCoreSyncAuthority) { self.handle = handle; self.owner = owner }
    deinit { crest_sync_transaction_release(handle) }
    func seal() throws -> Bool {
        var accepted: Int32 = 0
        let result = crest_sync_transaction_seal(handle, &accepted)
        guard result == CREST_OK else { throw BrowserCoreSyncAuthority.CoreError.rejected(result) }
        return accepted != 0
    }
    func publish() {
        precondition(crest_sync_transaction_commit(handle) == CREST_OK, "Lost core sync storage reservation")
        owner.publish(journal)
    }
}
#endif
