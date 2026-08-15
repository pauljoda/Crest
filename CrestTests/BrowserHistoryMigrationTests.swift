import Foundation
import SQLite3
import XCTest
@testable import Crest

final class BrowserHistoryMigrationTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testSafariHistoryDatabaseImportsVisitsAndMergesNormalizedURLs() async throws {
        let databaseURL = try makeDatabase(statements: [
            "CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT NOT NULL)",
            "CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL, title TEXT)",
            "INSERT INTO history_items VALUES (1, 'https://example.com/path#one')",
            "INSERT INTO history_items VALUES (2, 'https://example.com/path#two')",
            "INSERT INTO history_items VALUES (3, 'javascript:alert(1)')",
            "INSERT INTO history_visits VALUES (1, 1, 700000000, 'Earlier')",
            "INSERT INTO history_visits VALUES (2, 1, 700000100, 'Current title')",
            "INSERT INTO history_visits VALUES (3, 2, 700000200, 'Newest')",
            "INSERT INTO history_visits VALUES (4, 3, 700000300, 'Unsupported')",
        ])

        let imported = try await BrowserHistoryMigration.read(
            from: databaseURL,
            source: .safari,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let space = try XCTUnwrap(imported.spaces.first)
        let entry = try XCTUnwrap(space.history.first)

        XCTAssertEqual(space.name, "Imported History from Safari")
        XCTAssertEqual(imported.summary.historyEntryCount, 1)
        XCTAssertEqual(entry.url.absoluteString, "https://example.com/path")
        XCTAssertEqual(entry.title, "Newest")
        XCTAssertEqual(entry.visitCount, 3)
        XCTAssertEqual(
            entry.firstVisitedAt,
            Date(timeIntervalSinceReferenceDate: 700_000_000)
        )
        XCTAssertEqual(
            entry.lastVisitedAt,
            Date(timeIntervalSinceReferenceDate: 700_000_200)
        )
        XCTAssertEqual(space.tabs.count, 1)
        XCTAssertNil(space.tabs.first?.url)
    }

    func testChromeHistoryDatabaseUsesChromiumEpochAndStripsCredentials() async throws {
        let databaseURL = try makeChromiumDatabase(
            url: "https://user:secret@chromium.org/docs",
            title: "Chromium",
            firstVisit: 13_344_473_600_000_000,
            lastVisit: 13_344_473_700_000_000
        )

        let imported = try await BrowserHistoryMigration.read(
            from: databaseURL,
            source: .chrome,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let entry = try XCTUnwrap(imported.spaces.first?.history.first)

        XCTAssertEqual(imported.spaces.first?.name, "Imported History from Chrome")
        XCTAssertEqual(entry.url.absoluteString, "https://chromium.org/docs")
        XCTAssertEqual(entry.title, "Chromium")
        XCTAssertEqual(entry.visitCount, 2)
        XCTAssertEqual(entry.firstVisitedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(entry.lastVisitedAt, Date(timeIntervalSince1970: 1_700_000_100))
    }

    func testFirefoxPlacesDatabaseImportsVisitBounds() async throws {
        let databaseURL = try makeDatabase(statements: [
            "CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, last_visit_date INTEGER)",
            "CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, place_id INTEGER, visit_date INTEGER)",
            "INSERT INTO moz_places VALUES (1, 'https://mozilla.org/', 'Mozilla', 2, 1700000100000000)",
            "INSERT INTO moz_historyvisits VALUES (1, 1, 1700000000000000)",
            "INSERT INTO moz_historyvisits VALUES (2, 1, 1700000100000000)",
        ])

        let imported = try await BrowserHistoryMigration.read(
            from: databaseURL,
            source: .firefox,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let entry = try XCTUnwrap(imported.spaces.first?.history.first)

        XCTAssertEqual(imported.spaces.first?.name, "Imported History from Firefox")
        XCTAssertEqual(entry.url.absoluteString, "https://mozilla.org/")
        XCTAssertEqual(entry.visitCount, 2)
        XCTAssertEqual(entry.firstVisitedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(entry.lastVisitedAt, Date(timeIntervalSince1970: 1_700_000_100))
    }

    func testArcHistoryUsesChromiumDatabaseWithoutSharingRuntimeIdentity() async throws {
        let databaseURL = try makeChromiumDatabase(
            url: "https://arc.net/",
            title: "Arc",
            firstVisit: 13_344_473_600_000_000,
            lastVisit: 13_344_473_600_000_000
        )

        let first = try await BrowserHistoryMigration.read(
            from: databaseURL,
            source: .arc
        )
        let second = try await BrowserHistoryMigration.read(
            from: databaseURL,
            source: .arc
        )

        XCTAssertEqual(first.spaces.first?.name, "Imported History from Arc")
        XCTAssertEqual(first.spaces.first?.history.first?.title, "Arc")
        XCTAssertNotEqual(first.spaces.first?.id, second.spaces.first?.id)
        XCTAssertNotEqual(first.spaces.first?.profile, second.spaces.first?.profile)
        XCTAssertNotEqual(first.spaces.first?.history.first?.id, second.spaces.first?.history.first?.id)
    }

    func testHistoryImportRejectsAnUnrecognizedDatabase() async throws {
        let databaseURL = try makeDatabase(statements: [
            "CREATE TABLE unrelated (value TEXT)",
        ])

        do {
            _ = try await BrowserHistoryMigration.read(
                from: databaseURL,
                source: .safari
            )
            XCTFail("Expected the incompatible schema to be rejected")
        } catch {
            XCTAssertEqual(
                error as? BrowserHistoryMigrationError,
                .unrecognizedDatabase
            )
        }
    }

    private func makeChromiumDatabase(
        url: String,
        title: String,
        firstVisit: Int64,
        lastVisit: Int64
    ) throws -> URL {
        try makeDatabase(statements: [
            "CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, last_visit_time INTEGER)",
            "CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER)",
            "INSERT INTO urls VALUES (1, '\(url)', '\(title)', 2, \(lastVisit))",
            "INSERT INTO visits VALUES (1, 1, \(firstVisit))",
            "INSERT INTO visits VALUES (2, 1, \(lastVisit))",
        ])
    }

    private func makeDatabase(statements: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrestHistoryMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        let databaseURL = directory.appendingPathComponent("History.sqlite")

        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK,
              let database else {
            throw TestDatabaseError.openFailed
        }
        defer { sqlite3_close(database) }
        for statement in statements {
            guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
                throw TestDatabaseError.statementFailed
            }
        }
        return databaseURL
    }
}

private enum TestDatabaseError: Error {
    case openFailed
    case statementFailed
}

/// History leaving the single session blob for a key of its own per Space.
@MainActor
final class BrowserHistoryStorageMigrationTests: XCTestCase {
    private typealias Storage = UserDefaultsBrowserSessionPersistence

    func testLegacySessionHistoryMovesIntoOneKeyPerSpace() async throws {
        let suiteName = "BrowserHistoryStorageMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var legacy = BrowserSession.preview
        for spaceIndex in legacy.spaces.indices {
            legacy.spaces[spaceIndex].history = Self.history(
                inSpace: spaceIndex,
                entryCount: 12
            )
        }
        defaults.set(try JSONEncoder().encode(legacy), forKey: Storage.legacyCoreKey)
        let persistence = UserDefaultsBrowserSessionPersistence(
            defaults: defaults,
            faviconStore: InMemoryBrowserFaviconStore()
        )

        let migrated = try XCTUnwrap(persistence.load())
        await persistence.flushPendingSaves()

        XCTAssertEqual(migrated.spaces.map(\.history), legacy.spaces.map(\.history))
        for space in legacy.spaces {
            let data = try XCTUnwrap(
                defaults.data(forKey: Storage.historyKey(for: space.id)),
                "Each Space's history has to land under its own key."
            )
            XCTAssertEqual(
                try JSONDecoder().decode([BrowserHistoryEntry].self, from: data),
                space.history
            )
        }
        let core = try JSONDecoder().decode(
            BrowserSession.self,
            from: try XCTUnwrap(defaults.data(forKey: Storage.coreKey))
        )
        XCTAssertTrue(
            core.spaces.allSatisfy(\.history.isEmpty),
            "History must stop riding along with every session save."
        )
    }

    func testHistoryStorageStillEnforcesThePerSpaceCap() async throws {
        let suiteName = "BrowserHistoryStorageMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var legacy = BrowserSession.preview
        let overflowingSpaceID = legacy.spaces[0].id
        legacy.spaces[0].history = Self.history(
            inSpace: 0,
            entryCount: BrowserSession.maximumHistoryEntriesPerSpace + 10
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: Storage.legacyCoreKey)
        let faviconStore = InMemoryBrowserFaviconStore()
        let migrating = UserDefaultsBrowserSessionPersistence(
            defaults: defaults,
            faviconStore: faviconStore
        )
        _ = try XCTUnwrap(migrating.load())
        await migrating.flushPendingSaves()

        let relaunched = UserDefaultsBrowserSessionPersistence(
            defaults: defaults,
            faviconStore: faviconStore
        )
        let loaded = try XCTUnwrap(relaunched.load())

        XCTAssertEqual(
            loaded.space(id: overflowingSpaceID)?.history.count,
            BrowserSession.maximumHistoryEntriesPerSpace
        )
        XCTAssertEqual(
            loaded.space(id: overflowingSpaceID)?.history.first,
            legacy.spaces[0].history.first,
            "The cap drops the oldest entries, exactly as recording a visit does."
        )
    }

    private static func history(inSpace spaceIndex: Int, entryCount: Int) -> [BrowserHistoryEntry] {
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<entryCount).map { index in
            BrowserHistoryEntry(
                url: URL(string: "https://example.com/space-\(spaceIndex)/entry-\(index)")!,
                title: "Space \(spaceIndex) entry \(index)",
                firstVisitedAt: epoch,
                lastVisitedAt: epoch.addingTimeInterval(Double(entryCount - index)),
                visitCount: index % 5 + 1
            )
        }
    }
}
