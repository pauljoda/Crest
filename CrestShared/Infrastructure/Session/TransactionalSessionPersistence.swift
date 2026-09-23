import Foundation
import SQLite3

/// Platform storage for core checkpoints. Session parts and the sync journal
/// share a SQLite transaction; native image bytes remain in the favicon store.
/// The serial queue orders local saves, remote merges and upload acknowledgments.
final class BrowserTransactionalSessionPersistence: BrowserSessionPersisting, @unchecked Sendable {
    enum StorageError: Error { case sqlite(Int32), invalidCheckpoint, unsupportedVersion, incompleteSession, interruptedRestore }
    let url: URL
    private let queue = DispatchQueue(label: "com.pauldavis.crest.core-storage", qos: .utility)
    private var db: OpaquePointer?
    private let favicons: any BrowserFaviconStoring
    private var saveError: Error?
    /// The installed release's selection, carried from the legacy store when
    /// this launch migrated it. Checkpoints never store selection.
    private var migratedLegacySelection: BrowserLegacySessionSelection?
    var journalPersistence: BrowserSyncJournalPersisting { JournalPersistence(owner: self) }

    init(url: URL, favicons: any BrowserFaviconStoring) throws {
        self.url = url
        self.favicons = favicons
        guard !FileManager.default.fileExists(atPath: BrowserSessionRecovery.restoreMarker(for: url).path) else {
            throw StorageError.interruptedRestore
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // A writable SQLite connection can truncate a damaged WAL even when
        // opening the main database fails. Validate existing files read-only
        // before allowing that connection to alter recovery evidence.
        if FileManager.default.fileExists(atPath: url.path) {
            var validation: OpaquePointer?
            // A cleanly closed WAL database has no sidecar. Apple's read-only
            // VFS cannot recreate it; inspect that standalone checkpoint without
            // WAL discovery. With a sidecar present, SQLite must read it normally.
            let standalone = !FileManager.default.fileExists(atPath: url.path + "-wal")
            let source = standalone ? url.absoluteString + "?immutable=1" : url.path
            let opened = sqlite3_open_v2(source, &validation,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI, nil)
            guard opened == SQLITE_OK, let validation else {
                if let validation { sqlite3_close(validation) }
                throw StorageError.sqlite(opened)
            }
            db = validation
            do {
                let version = try storageVersion()
                guard version == 0 || version == 1 else { throw StorageError.unsupportedVersion }
                if version == 1 {
                    _ = try readSession()
                    if let data = try read("journal") { _ = try BrowserSyncJournal.decodeSnapshot(data) }
                }
            } catch { sqlite3_close(validation); db = nil; throw error }
            sqlite3_close(validation)
            db = nil
        }
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &connection,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw StorageError.sqlite(result)
        }
        db = connection
        do {
            sqlite3_busy_timeout(db, 2000)
            let version = try storageVersion()
            guard version == 0 || version == 1 else { throw StorageError.unsupportedVersion }
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try transaction {
                try execute("CREATE TABLE IF NOT EXISTS checkpoint (part TEXT PRIMARY KEY, data BLOB NOT NULL)")
                try execute("PRAGMA user_version=1")
            }
            // Decode both parts before allowing launch to overwrite anything.
            _ = try readSession()
            if let data = try read("journal") { _ = try BrowserSyncJournal.decodeSnapshot(data) }
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { if let db { sqlite3_close(db) } }

    private func storageVersion() throws -> Int32 {
        try statement("PRAGMA user_version") { stmt in
            guard sqlite3_step(stmt) == SQLITE_ROW else { throw StorageError.invalidCheckpoint }
            return sqlite3_column_int(stmt, 0)
        }
    }

    /// Once per successful launch, preserve a complete database snapshot. SQLite's
    /// backup API includes committed WAL pages without copying live sidecars.
    func saveRecoveryCheckpoint() throws {
        try queue.sync {
            guard try readSession() != nil, let journal = try read("journal") else { return }
            _ = try BrowserSyncJournal.decodeSnapshot(journal)
            let destination = BrowserSessionRecovery.checkpointURL(for: url)
            let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".sqlite")
            defer { BrowserSessionRecovery.removeTemporaryDatabase(temporary) }
            var target: OpaquePointer?
            let opened = sqlite3_open(temporary.path, &target)
            guard opened == SQLITE_OK, let target else {
                if let target { sqlite3_close(target) }
                throw StorageError.sqlite(opened)
            }
            do {
                guard let backup = sqlite3_backup_init(target, "main", db, "main") else {
                    throw StorageError.sqlite(sqlite3_errcode(target))
                }
                let step = sqlite3_backup_step(backup, -1)
                let finished = sqlite3_backup_finish(backup)
                guard step == SQLITE_DONE, finished == SQLITE_OK else {
                    throw StorageError.sqlite(step == SQLITE_DONE ? finished : step)
                }
                let mode = sqlite3_exec(target, "PRAGMA journal_mode=DELETE", nil, nil, nil)
                guard mode == SQLITE_OK else { throw StorageError.sqlite(mode) }
            } catch { sqlite3_close(target); throw error }
            guard sqlite3_close(target) == SQLITE_OK else { throw StorageError.sqlite(SQLITE_BUSY) }
            try BrowserSessionRecovery.atomicReplace(temporary, destination: destination)
        }
    }

    /// Called only before stores or background staging exist. Legacy data is
    /// retained for rollback; an existing checkpoint always wins over it.
    func migrateIfNeeded(session: @autoclosure () throws -> BrowserSession?,
        journal: @autoclosure () throws -> BrowserSyncJournal?,
        legacySelection: @autoclosure () -> BrowserLegacySessionSelection? = nil) throws {
        try queue.sync {
            guard try read("core") == nil else { return }
            guard let session = try session() else { return }
            migratedLegacySelection = legacySelection()
            let journal = try journal() ?? BrowserSyncJournal()
            try transaction {
                try writeSession(session, scope: .everything, checkpoint: nil)
                try write("journal", data: journal.encodedSnapshot())
            }
            reconcileFavicons(session, scope: .everything)
        }
    }

    func load() -> BrowserSession? {
        queue.sync {
            // Initialization validates the file; later failures must preserve it
            // rather than masquerading as an empty first-launch session.
            do { return try readSession() }
            catch { preconditionFailure("Cannot restore the core checkpoint: \(error)") }
        }
    }

    /// A checkpoint written before selection became window state still names
    /// one; a first upgrade carries the installed release's instead.
    func loadLegacySelection() -> BrowserLegacySessionSelection? {
        queue.sync { migratedLegacySelection ?? BrowserLegacySessionSelection.decode(try? read("core")) }
    }

    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope) {
        enqueue(session, scope: scope, checkpoint: nil)
    }
    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope, checkpoint: any BrowserSessionCheckpoint) {
        enqueue(session, scope: scope, checkpoint: checkpoint)
    }
    private func enqueue(_ session: BrowserSession, scope: BrowserSessionSaveScope,
        checkpoint: (any BrowserSessionCheckpoint)?) {
        queue.async { [self] in
            do {
                // A failed narrow save may have missed another part. Retry the
                // complete accepted snapshot before allowing journal writes.
                let effectiveScope: BrowserSessionSaveScope = saveError == nil ? scope : .everything
                try transaction { try writeSession(session, scope: effectiveScope, checkpoint: checkpoint) }
                saveError = nil
                reconcileFavicons(session, scope: effectiveScope)
            } catch { saveError = error }
        }
    }
    func flushPendingSaves() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    func owns(_ persistence: any BrowserSyncJournalPersisting) -> Bool {
        (persistence as? JournalPersistence)?.owner === self
    }

    /// Core validation/reservation has already succeeded. SQLite COMMIT is the
    /// durability boundary; only afterward may the caller publish either value.
    func commit(_ session: BrowserSession, checkpoint: any BrowserSessionCheckpoint,
        journal: BrowserSyncJournal? = nil) throws {
        try queue.sync {
            let journalData = try journal?.encodedSnapshot()
            try transaction {
                try writeSession(session, scope: .everything, checkpoint: checkpoint)
                if let journalData { try write("journal", data: journalData) }
            }
            saveError = nil
            reconcileFavicons(session, scope: .everything)
        }
    }

    private func writeSession(_ session: BrowserSession, scope: BrowserSessionSaveScope,
        checkpoint: (any BrowserSessionCheckpoint)?) throws {
        let initial = try read("core") == nil
        if scope.writesCore || initial {
            let data: Data
            if let checkpoint {
                guard let encoded = checkpoint.coreData() else { throw StorageError.invalidCheckpoint }
                data = encoded
            } else {
                var compact = BrowserCoreSessionAuthority.compact(session)
                for index in compact.spaces.indices { compact.spaces[index].history = [] }
                data = try JSONEncoder().encode(compact)
            }
            try write("core", data: data)
            let retained = Set(session.spaces.map { "history." + $0.id.rawValue.uuidString })
            for key in try keys(prefix: "history.") where !retained.contains(key) { try remove(key) }
        }
        for space in session.spaces {
            if !initial && !scope.history.covers(space.id) {
                if try read("history." + space.id.rawValue.uuidString) != nil { continue }
            }
            let data: Data
            if let checkpoint {
                guard let encoded = checkpoint.historyData(in: space.id) else { throw StorageError.invalidCheckpoint }
                data = encoded
            } else { data = try JSONEncoder().encode(space.history) }
            try write("history." + space.id.rawValue.uuidString, data: data)
        }
    }

    private func readSession() throws -> BrowserSession? {
        guard let data = try read("core") else { return nil }
        var session = try JSONDecoder().decode(BrowserSession.self, from: data)
        for index in session.spaces.indices {
            guard let history = try read("history." + session.spaces[index].id.rawValue.uuidString) else {
                throw StorageError.incompleteSession
            }
            session.spaces[index].history = try JSONDecoder().decode([BrowserHistoryEntry].self, from: history)
            for tab in session.spaces[index].tabs.indices {
                session.spaces[index].tabs[tab].faviconData = favicons.favicon(tabID: session.spaces[index].tabs[tab].id)
            }
        }
        return session
    }
    private func reconcileFavicons(_ session: BrowserSession, scope: BrowserSessionSaveScope) {
        for tab in session.spaces.flatMap(\.tabs) where scope.favicons.covers(tab.id) {
            favicons.reconcile(tab.faviconData, tabID: tab.id)
        }
        if scope.writesCore || scope.favicons.isEverything {
            favicons.pruneFavicons(keeping: Set(session.spaces.flatMap { $0.tabs.map(\.id) }))
        }
    }

    private final class JournalPersistence: BrowserSyncJournalPersisting {
        let owner: BrowserTransactionalSessionPersistence
        init(owner: BrowserTransactionalSessionPersistence) { self.owner = owner }
        func load() throws -> BrowserSyncJournal? {
            try owner.queue.sync {
                guard let data = try owner.read("journal") else { return nil }
                return try BrowserSyncJournal.decodeSnapshot(data)
            }
        }
        func save(_ journal: BrowserSyncJournal) throws {
            try owner.queue.sync {
                if let error = owner.saveError { throw error }
                try owner.transaction { try owner.write("journal", data: journal.encodedSnapshot()) }
            }
        }
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch { try? execute("ROLLBACK"); throw error }
    }
    private func execute(_ sql: String) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw StorageError.sqlite(result) }
    }
    private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var value: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &value, nil)
        guard result == SQLITE_OK, let value else { throw StorageError.sqlite(result) }
        defer { sqlite3_finalize(value) }
        return try body(value)
    }
    private func bind(_ key: String, to stmt: OpaquePointer) throws {
        let result = sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard result == SQLITE_OK else { throw StorageError.sqlite(result) }
    }
    private func read(_ key: String) throws -> Data? {
        try statement("SELECT data FROM checkpoint WHERE part=?") { stmt in
            try bind(key, to: stmt)
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw StorageError.sqlite(result) }
            let count = Int(sqlite3_column_bytes(stmt, 0))
            guard count > 0, count <= 64 * 1024 * 1024, let bytes = sqlite3_column_blob(stmt, 0) else {
                throw StorageError.invalidCheckpoint
            }
            return Data(bytes: bytes, count: count)
        }
    }
    private func write(_ key: String, data: Data) throws {
        guard !data.isEmpty, data.count <= 64 * 1024 * 1024 else { throw StorageError.invalidCheckpoint }
        // Avoid dirtying unchanged pages, especially histories and acknowledgments.
        if try read(key) == data { return }
        try statement("INSERT INTO checkpoint(part,data) VALUES(?,?) ON CONFLICT(part) DO UPDATE SET data=excluded.data") { stmt in
            try bind(key, to: stmt)
            let bound = data.withUnsafeBytes {
                sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard bound == SQLITE_OK else { throw StorageError.sqlite(bound) }
            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE else { throw StorageError.sqlite(result) }
        }
    }
    private func keys(prefix: String) throws -> [String] {
        try statement("SELECT part FROM checkpoint WHERE part LIKE ?") { stmt in
            try bind(prefix + "%", to: stmt)
            var keys: [String] = []
            while true {
                let result = sqlite3_step(stmt)
                if result == SQLITE_DONE { return keys }
                guard result == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { throw StorageError.sqlite(result) }
                keys.append(String(cString: text))
            }
        }
    }
    private func remove(_ key: String) throws {
        try statement("DELETE FROM checkpoint WHERE part=?") { stmt in
            try bind(key, to: stmt)
            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE else { throw StorageError.sqlite(result) }
        }
    }
}
