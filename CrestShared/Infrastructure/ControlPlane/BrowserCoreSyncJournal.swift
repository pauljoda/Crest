#if CREST_CORE_BACKED
import CrestCoreABI
import Foundation

/// A core snapshot never changes after creation. Swift value copies can safely
/// share its handle while each mutation prepares an independent next snapshot.
final class BrowserCoreSyncJournal: @unchecked Sendable {
    private let handle: UInt64
    private let preferences: BrowserSyncPreferences
    private static let byteLimit = 64 * 1024 * 1024

    convenience init(_ journal: BrowserSyncJournal) throws {
        try self.init(data: JSONEncoder().encode(journal), preferences: journal.preferences)
    }

    init(data: Data, preferences: BrowserSyncPreferences) throws {
        guard data.count <= Self.byteLimit else { throw JournalError.tooLarge }
        var handle: UInt64 = 0
        let result = data.withUnsafeBytes {
            crest_sync_journal_create($0.bindMemory(to: UInt8.self).baseAddress, data.count, &handle)
        }
        guard result == CREST_OK else { throw JournalError.rejected(result) }
        self.handle = handle
        self.preferences = preferences
    }

    private init(handle: UInt64, preferences: BrowserSyncPreferences) {
        self.handle = handle
        self.preferences = preferences
    }
    deinit { crest_sync_journal_release(handle) }

    func applying(_ operation: String, preferences: BrowserSyncPreferences, arguments: [String: Any]) throws -> BrowserCoreSyncJournal {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "operation": operation, "preferences": try BrowserCoreSync.value(preferences),
            "arguments": arguments
        ])
        guard data.count <= Self.byteLimit else { throw JournalError.tooLarge }
        var next: UInt64 = 0
        var errorQuery: UInt64 = 0
        let result = data.withUnsafeBytes {
            crest_sync_journal_apply_checked(handle, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &next, &errorQuery)
        }
        if errorQuery != 0 { let _: Bool = try BrowserCoreSync.readQuery(errorQuery) }
        if result == CREST_INVALID_STATE { throw BrowserSyncError.logicalClockExhausted }
        guard result == CREST_OK else { throw JournalError.rejected(result) }
        return BrowserCoreSyncJournal(handle: next, preferences: preferences)
    }

    func read(preferences: BrowserSyncPreferences) throws -> Data {
        if preferences == self.preferences { return try read() }
        return try applying("preferences", preferences: preferences, arguments: [:]).read()
    }

    func read() throws -> Data {
        var length = 0
        let measured = crest_sync_journal_read(handle, nil, 0, &length)
        guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= Self.byteLimit else {
            throw JournalError.rejected(measured)
        }
        let capacity = length
        var data = Data(count: capacity)
        let result = data.withUnsafeMutableBytes {
            crest_sync_journal_read(handle, $0.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
        }
        guard result == CREST_OK, length <= capacity else { throw JournalError.rejected(result) }
        return data.prefix(length)
    }

    private enum JournalError: Error { case tooLarge, rejected(Int32) }
}
#endif
