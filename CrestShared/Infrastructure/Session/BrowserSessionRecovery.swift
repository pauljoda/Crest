import Darwin
import Foundation
import SQLite3

struct BrowserSessionStartupFailure: Error {
    let storeURL: URL?
    let underlying: Error

    /// The file was written by a newer release, which a restore must not undo.
    var requiresNewerApp: Bool {
        if case .storageFromNewerApp = underlying as? Rejection { return true }
        if case BrowserSyncError.unsupportedSchema = underlying { return true }
        return false
    }

    var checkpointDate: Date? {
        guard !requiresNewerApp, let storeURL else { return nil }
        return try? BrowserSessionRecovery.checkpointURL(for: storeURL)
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func restore() throws {
        guard !requiresNewerApp, let storeURL else { throw BrowserSessionRecovery.RecoveryError.unavailable }
        try BrowserSessionRecovery.restore(storeURL)
    }
}

/// Filesystem recovery runs from the startup failure screen, when no core has
/// the session file open. Originals and the last startup checkpoint are
/// retained after restore.
///
/// TRANSITIONAL until the core owns recovery (3b): the core writes the
/// recovery checkpoint when it opens the file; restoring it still reads and
/// rewrites the copied checkpoint here, never the live file.
enum BrowserSessionRecovery {
    enum RecoveryError: Error {
        /// Nothing may be restored over this file.
        case unavailable
        /// The recovery checkpoint does not hold a complete session and journal.
        case incompleteCheckpoint
        case sqlite(Int32)
    }

    /// The session file's name inside the core's storage directory.
    static let fileName = "session.sqlite"

    static func checkpointURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("recovery.sqlite")
    }
    static func restoreMarker(for url: URL) -> URL { url.appendingPathExtension("restore-pending") }
    static func cloudMarker(for url: URL) -> URL { url.appendingPathExtension("cloud-recovery") }

    static func removeTemporaryDatabase(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    static func atomicReplace(_ source: URL, destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    static func restore(_ url: URL) throws {
        let files = FileManager.default
        let directory = url.deletingLastPathComponent()
        let candidate = directory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { removeTemporaryDatabase(candidate) }
        try files.copyItem(at: checkpointURL(for: url), to: candidate)
        // Decode every session part and rotate only the journal's local identity.
        // Never touch the failed database unless this candidate is usable.
        try prepareCandidate(candidate)
        let preserved = directory.appendingPathComponent("Recovery-" + UUID().uuidString, isDirectory: true)
        try files.createDirectory(
            at: preserved, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            if files.fileExists(atPath: source.path) {
                try files.copyItem(at: source, to: preserved.appendingPathComponent(source.lastPathComponent))
            }
        }
        try Data(preserved.path.utf8).write(to: restoreMarker(for: url), options: .atomic)
        // Keep this marker until the matching cloud transport has durably opted
        // into a full merge. Its newer cursor cannot describe the older journal.
        try Data().write(to: cloudMarker(for: url), options: .atomic)
        for suffix in ["-wal", "-shm"] where files.fileExists(atPath: url.path + suffix) {
            try files.removeItem(atPath: url.path + suffix)
        }
        try atomicReplace(candidate, destination: url)
        try files.removeItem(at: restoreMarker(for: url))
    }

    /// Reads every part of a copied checkpoint, then gives its journal a new
    /// local device identity so the restored journal cannot reuse versions it
    /// issued after the checkpoint was taken.
    private static func prepareCandidate(_ url: URL) throws {
        let candidate = try Candidate(url: url)
        guard try candidate.userVersion() == 1, let core = try candidate.read("core") else {
            throw RecoveryError.incompleteCheckpoint
        }
        let session = try JSONDecoder().decode(BrowserSession.self, from: core)
        for space in session.spaces {
            guard let history = try candidate.read("history." + space.id.rawValue.uuidString) else {
                throw RecoveryError.incompleteCheckpoint
            }
            _ = try JSONDecoder().decode([BrowserHistoryEntry].self, from: history)
        }
        guard let journal = try candidate.read("journal") else { throw RecoveryError.incompleteCheckpoint }
        try candidate.write(
            "journal", data: BrowserSyncJournal.decodeSnapshot(journal).recoveredForNewDevice().encodedSnapshot())
    }

    static func prepareCloudRecovery(storeURL: URL, environment: BrowserLaunchEnvironment) throws {
        let marker = cloudMarker(for: storeURL)
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let persistence: any BrowserCloudSyncStatePersisting
        if environment.requiresIsolation {
            guard let configuration = BrowserCloudSyncConfiguration.configured()?.isolated(for: environment),
                let id = environment.persistentIsolationID,
                let isolated = FileBrowserCloudSyncStatePersistence.isolated(
                    localProfileID: id, configuration: configuration)
            else { return }
            persistence = isolated
        } else {
            persistence =
                FileBrowserCloudSyncStatePersistence.production()
                ?? UserDefaultsBrowserCloudSyncStatePersistence()
        }
        try resetCloudCursor(persistence)
        try FileManager.default.removeItem(at: marker)
    }

    static func resetCloudCursor(_ persistence: any BrowserCloudSyncStatePersisting) throws {
        var state = try persistence.load() ?? BrowserCloudSyncState()
        state.engineStateSerialization = nil
        state.systemFields = BrowserCloudRecordSystemFields()
        state.conflictResolution = nil
        state.requiresFullPull = true
        // Account confirmation remains mandatory if the account changed.
        try persistence.save(state)
    }
}

/// One connection to a copied recovery checkpoint, which only restore opens.
private final class Candidate {
    private let db: OpaquePointer

    init(url: URL) throws {
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw BrowserSessionRecovery.RecoveryError.sqlite(result)
        }
        db = connection
    }

    deinit { sqlite3_close(db) }

    func userVersion() throws -> Int32 {
        try statement("PRAGMA user_version") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw BrowserSessionRecovery.RecoveryError.incompleteCheckpoint
            }
            return sqlite3_column_int(statement, 0)
        }
    }

    func read(_ part: String) throws -> Data? {
        try statement("SELECT data FROM checkpoint WHERE part=?") { statement in
            try bind(part, to: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw BrowserSessionRecovery.RecoveryError.sqlite(result) }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else {
                throw BrowserSessionRecovery.RecoveryError.incompleteCheckpoint
            }
            return Data(bytes: bytes, count: count)
        }
    }

    func write(_ part: String, data: Data) throws {
        try statement("UPDATE checkpoint SET data=? WHERE part=?") { statement in
            let bound = data.withUnsafeBytes {
                sqlite3_bind_blob(
                    statement, 1, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                )
            }
            guard bound == SQLITE_OK else { throw BrowserSessionRecovery.RecoveryError.sqlite(bound) }
            let result = sqlite3_bind_text(statement, 2, part, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard result == SQLITE_OK else { throw BrowserSessionRecovery.RecoveryError.sqlite(result) }
            let stepped = sqlite3_step(statement)
            guard stepped == SQLITE_DONE else { throw BrowserSessionRecovery.RecoveryError.sqlite(stepped) }
        }
    }

    private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var value: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &value, nil)
        guard result == SQLITE_OK, let value else { throw BrowserSessionRecovery.RecoveryError.sqlite(result) }
        defer { sqlite3_finalize(value) }
        return try body(value)
    }

    private func bind(_ part: String, to statement: OpaquePointer) throws {
        let result = sqlite3_bind_text(statement, 1, part, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard result == SQLITE_OK else { throw BrowserSessionRecovery.RecoveryError.sqlite(result) }
    }
}
