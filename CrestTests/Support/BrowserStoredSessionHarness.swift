import Foundation
import SQLite3
import XCTest

@testable import Crest

/// A session the core keeps in its own file in a temporary directory, opened
/// the way a launch opens it, and read back the way the next launch would.
@MainActor
final class BrowserStoredSessionHarness {
    // MARK: - Types

    enum HarnessError: Error {
        case sqlite(Int32)
    }

    // MARK: - Variables

    let directory: URL
    let favicons: InMemoryBrowserFaviconStore
    let core: CrestCore
    let store: BrowserStore
    var url: URL { directory.appendingPathComponent("session.sqlite") }

    // MARK: - Initializers

    /// Gives a new file `session` and `journal` as its first session, then
    /// opens it with a window on its launch Space.
    init(
        session: BrowserSession, journal: BrowserSyncJournal? = nil,
        favicons: InMemoryBrowserFaviconStore = InMemoryBrowserFaviconStore()
    ) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.favicons = favicons
        core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        try BrowserInstalledRelease.adopt(session, journal: journal, into: core, favicons: favicons)
        store = try Self.open(core, favicons: favicons)
    }

    /// Opens the file a harness left behind, as a launch after a crash would.
    private init(copying directory: URL, favicons: InMemoryBrowserFaviconStore) throws {
        self.directory = directory
        self.favicons = favicons
        core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        store = try Self.open(core, favicons: favicons)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func open(_ core: CrestCore, favicons: InMemoryBrowserFaviconStore) throws -> BrowserStore {
        let stored = try XCTUnwrap(BrowserCoreStoredSession.load(core: core, favicons: favicons))
        let family = BrowserStoreFamily(stored: stored, storage: core, favicons: favicons)
        return BrowserStore(
            credentialVault: InMemoryCredentialVault(), syncCoordinator: BrowserSyncCoordinator(core: stored.sync),
            browsingMode: .standard, family: family, core: core)
    }

    // MARK: - Actions - Launches

    /// The file as the process would leave it if it stopped now, opened by a
    /// new launch. This harness keeps its own core and file.
    func relaunch() async throws -> BrowserStoredSessionHarness {
        await store.flushPendingSyncPersistence()
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            try FileManager.default.copyItem(
                atPath: url.path + suffix, toPath: copy.appendingPathComponent(url.lastPathComponent).path + suffix)
        }
        return try BrowserStoredSessionHarness(copying: copy, favicons: favicons)
    }

    // MARK: - Actions - Reading the file

    /// The session and journal the file holds now.
    func stored() throws -> (session: BrowserSession, journal: BrowserSyncJournal?) {
        try withConnection { connection in
            let core = try XCTUnwrap(try Self.read("core", in: connection))
            var session = try JSONDecoder().decode(BrowserSession.self, from: core)
            for index in session.spaces.indices {
                let history = try XCTUnwrap(
                    try Self.read("history." + session.spaces[index].id.rawValue.uuidString, in: connection))
                session.spaces[index].history = try JSONDecoder().decode([BrowserHistoryEntry].self, from: history)
                for tab in session.spaces[index].tabs.indices {
                    session.spaces[index].tabs[tab].faviconData = favicons.favicon(
                        tabID: session.spaces[index].tabs[tab].id)
                }
            }
            let journal = try Self.read("journal", in: connection).map(BrowserSyncJournal.decodeSnapshot)
            return (session, journal)
        }
    }

    /// One stored part's bytes, exactly as the file holds them.
    func storedPart(_ part: String) throws -> Data? {
        try withConnection { try Self.read(part, in: $0) }
    }

    /// The Space the device table the file holds records `window` showing,
    /// or nil when it keeps no record of that window.
    func storedShownSpace(of window: BrowserWindowID) throws -> UUID? {
        try withConnection { connection in
            var statement: OpaquePointer?
            let prepared = sqlite3_prepare_v2(
                connection, "SELECT shown_space FROM device_window WHERE id=?", -1, &statement, nil)
            guard prepared == SQLITE_OK, let statement else { throw HarnessError.sqlite(prepared) }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(
                statement, 1, window.rawValue.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW, let shown = sqlite3_column_text(statement, 0) else {
                throw HarnessError.sqlite(result)
            }
            return UUID(uuidString: String(cString: shown))
        }
    }

    // MARK: - Actions - Faults

    /// Makes the file refuse every write to `part`, as a full disk or a failing
    /// device refuses one in the middle of a transaction.
    func refuseWrites(to part: String) throws {
        try withConnection(writable: true) { connection in
            for operation in ["INSERT", "UPDATE"] {
                try Self.execute(
                    "CREATE TRIGGER refuse_\(operation) BEFORE \(operation) ON checkpoint WHEN NEW.part = '\(part)' "
                        + "BEGIN SELECT RAISE(ABORT, 'refused'); END", in: connection)
            }
        }
    }

    func acceptWrites() throws {
        try withConnection(writable: true) { connection in
            try Self.execute("DROP TRIGGER refuse_INSERT", in: connection)
            try Self.execute("DROP TRIGGER refuse_UPDATE", in: connection)
        }
    }

    // MARK: - Actions - SQLite

    private func withConnection<T>(writable: Bool = false, _ body: (OpaquePointer) throws -> T) throws -> T {
        var connection: OpaquePointer?
        let flags = writable ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
        let opened = sqlite3_open_v2(url.path, &connection, flags, nil)
        guard opened == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw HarnessError.sqlite(opened)
        }
        defer { sqlite3_close(connection) }
        sqlite3_busy_timeout(connection, 2000)
        return try body(connection)
    }

    private static func execute(_ sql: String, in connection: OpaquePointer) throws {
        let result = sqlite3_exec(connection, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw HarnessError.sqlite(result) }
    }

    private static func read(_ part: String, in connection: OpaquePointer) throws -> Data? {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(connection, "SELECT data FROM checkpoint WHERE part=?", -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw HarnessError.sqlite(prepared) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, part, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
            throw HarnessError.sqlite(result)
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }
}
