import Foundation
import SQLite3
import XCTest
@testable import CrestMobile

@MainActor
final class MobileBrowserPortableArchiveTests: XCTestCase {
    func testFirefoxOpenTabsImportCreatesFreshMobileSpaces() throws {
        let json = """
        {
          "selectedWindow": 1,
          "windows": [{
            "title": "Mobile Firefox",
            "selected": 1,
            "tabs": [{
              "index": 1,
              "entries": [{"url":"https://mozilla.org/","title":"Mozilla"}]
            }]
          }]
        }
        """

        let first = try BrowserTabMigration.decode(
            Data(json.utf8),
            source: .firefox
        )
        let second = try BrowserTabMigration.decode(
            Data(json.utf8),
            source: .firefox
        )

        XCTAssertEqual(first.spaces.first?.name, "Mobile Firefox")
        XCTAssertEqual(first.spaces.first?.tabs.first?.title, "Mozilla")
        XCTAssertNotEqual(first.spaces.first?.profile, second.spaces.first?.profile)
    }

    func testChromiumHistoryDatabaseImportsIntoAFreshMobileSpace() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrestMobileHistory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("History")
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK,
              let database else {
            return XCTFail("Could not create the Chromium history fixture")
        }
        let statements = [
            "CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, last_visit_time INTEGER)",
            "CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER)",
            "INSERT INTO urls VALUES (1, 'https://example.com/', 'Example', 1, 13344473600000000)",
            "INSERT INTO visits VALUES (1, 1, 13344473600000000)",
        ]
        for statement in statements {
            guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
                sqlite3_close(database)
                return XCTFail("Could not populate the Chromium history fixture")
            }
        }
        sqlite3_close(database)

        let imported = try await BrowserHistoryMigration.read(
            from: databaseURL,
            source: .chrome
        )

        XCTAssertEqual(imported.spaces.first?.history.first?.title, "Example")
        XCTAssertEqual(imported.spaces.first?.name, "Imported History from Chrome")
        XCTAssertNotEqual(imported.spaces.first?.profile, BrowserSession.preview.spaces.first?.profile)
    }

    func testStandardBookmarkHTMLImportsIntoAFreshIsolatedSpace() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
          <DT><H3>Mobile</H3>
          <DL><p><DT><A HREF="https://example.com/">Example</A></DL><p>
        </DL><p>
        """

        let first = try BrowserBookmarkMigration.decode(
            Data(html.utf8),
            source: .htmlBookmarks
        )
        let second = try BrowserBookmarkMigration.decode(
            Data(html.utf8),
            source: .htmlBookmarks
        )

        XCTAssertEqual(first.spaces.first?.tabs.first?.title, "Example")
        XCTAssertNotEqual(first.spaces.first?.profile, second.spaces.first?.profile)
        XCTAssertNotEqual(first.spaces.first?.tabs.first?.id, second.spaces.first?.tabs.first?.id)
    }

    func testCanonicalExportFilenameCarriesTheImportableJSONExtension() {
        XCTAssertTrue(BrowserPortableArchive.defaultFilename.hasSuffix(".json"))
    }

    func testPortableArchiveRoundTripCreatesFreshSpaceAndProfileIDs() throws {
        let source = BrowserSession.preview
        let sourceIDs = Set(source.spaces.map(\.id))
        let sourceProfileIDs = Set(source.spaces.map(\.profile.id))

        let imported = try BrowserPortableArchive.decode(
            BrowserPortableArchive.encode(session: source)
        ).materialize()

        XCTAssertEqual(imported.spaces.count, source.spaces.count)
        XCTAssertTrue(Set(imported.spaces.map(\.id)).isDisjoint(with: sourceIDs))
        XCTAssertTrue(
            Set(imported.spaces.map(\.profile.id)).isDisjoint(
                with: sourceProfileIDs
            )
        )
        XCTAssertTrue(
            imported.spaces.flatMap(\.tabs).allSatisfy {
                $0.faviconData == nil
            }
        )
    }

    func testMobileStoreImportAppendsAndPersistsPortableSpaces() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(
            session: .preview,
            persistence: persistence
        )
        let originalSpaceCount = store.session.spaces.count
        let imported = try BrowserPortableArchive(
            session: .preview
        ).materialize()

        try store.importPortableArchive(imported)

        XCTAssertEqual(
            store.session.spaces.count,
            originalSpaceCount + imported.spaces.count
        )
        XCTAssertEqual(store.session.selectedSpaceID, imported.spaces[0].id)
        XCTAssertEqual(persistence.session, store.session)
    }
}
