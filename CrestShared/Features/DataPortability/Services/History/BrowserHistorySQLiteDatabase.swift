import Foundation
import SQLite3

final class BrowserHistorySQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            throw BrowserHistoryMigrationError.unrecognizedDatabase
        }
        handle = database
        sqlite3_extended_result_codes(database, 1)
        sqlite3_busy_timeout(database, 1_000)
        sqlite3_exec(database, "PRAGMA query_only = ON", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA trusted_schema = OFF", nil, nil, nil)
        sqlite3_limit(database, SQLITE_LIMIT_LENGTH, 8 * 1_024 * 1_024)
        sqlite3_limit(database, SQLITE_LIMIT_SQL_LENGTH, 64 * 1_024)
        sqlite3_limit(database, SQLITE_LIMIT_COLUMN, 64)
        sqlite3_limit(database, SQLITE_LIMIT_ATTACHED, 0)
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func records(
        for source: BrowserHistoryMigrationSource
    ) throws -> [BrowserHistorySQLiteRecord] {
        let sql: String
        switch source {
        case .safari:
            sql = """
                SELECT hi.url,
                       COALESCE((
                           SELECT latest.title
                           FROM history_visits AS latest
                           WHERE latest.history_item = hi.id
                             AND latest.title IS NOT NULL
                             AND latest.title <> ''
                           ORDER BY latest.visit_time DESC
                           LIMIT 1
                       ), ''),
                       MIN(hv.visit_time),
                       MAX(hv.visit_time),
                       COUNT(hv.id)
                FROM history_items AS hi
                JOIN history_visits AS hv ON hv.history_item = hi.id
                GROUP BY hi.id, hi.url
                ORDER BY MAX(hv.visit_time) DESC
                LIMIT 5000
                """
        case .chrome, .arc:
            sql = """
                SELECT u.url,
                       COALESCE(u.title, ''),
                       MIN(v.visit_time),
                       MAX(v.visit_time),
                       CASE
                           WHEN u.visit_count > COUNT(v.id) THEN u.visit_count
                           ELSE COUNT(v.id)
                       END
                FROM urls AS u
                JOIN visits AS v ON v.url = u.id
                GROUP BY u.id, u.url, u.title, u.visit_count
                ORDER BY MAX(v.visit_time) DESC
                LIMIT 5000
                """
        case .firefox:
            sql = """
                SELECT p.url,
                       COALESCE(p.title, ''),
                       MIN(v.visit_date),
                       MAX(v.visit_date),
                       CASE
                           WHEN p.visit_count > COUNT(v.id) THEN p.visit_count
                           ELSE COUNT(v.id)
                       END
                FROM moz_places AS p
                JOIN moz_historyvisits AS v ON v.place_id = p.id
                GROUP BY p.id, p.url, p.title, p.visit_count
                ORDER BY MAX(v.visit_date) DESC
                LIMIT 5000
                """
        }
        return try query(sql)
    }

    private func query(_ sql: String) throws -> [BrowserHistorySQLiteRecord] {
        guard let handle else {
            throw BrowserHistoryMigrationError.unrecognizedDatabase
        }
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw migrationError(for: prepareResult)
        }
        defer { sqlite3_finalize(statement) }

        var records: [BrowserHistorySQLiteRecord] = []
        records.reserveCapacity(BrowserSession.maximumHistoryEntriesPerSpace)
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return records
            }
            guard result == SQLITE_ROW else {
                throw migrationError(for: result)
            }
            guard let url = string(in: statement, column: 0),
                let title = string(in: statement, column: 1)
            else { continue }
            records.append(
                BrowserHistorySQLiteRecord(
                    url: url,
                    title: title,
                    firstVisit: sqlite3_column_double(statement, 2),
                    lastVisit: sqlite3_column_double(statement, 3),
                    visitCount: Int(
                        min(
                            Int64(1_000_000_000),
                            max(Int64(1), sqlite3_column_int64(statement, 4))
                        )
                    )
                )
            )
        }
    }

    private func string(
        in statement: OpaquePointer,
        column: Int32
    ) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
            let bytes = sqlite3_column_text(statement, column)
        else { return nil }
        let byteCount = Int(sqlite3_column_bytes(statement, column))
        guard byteCount >= 0, byteCount <= 8 * 1_024 * 1_024 else { return nil }
        return String(
            decoding: UnsafeBufferPointer(start: bytes, count: byteCount),
            as: UTF8.self
        )
    }

    private func migrationError(for result: Int32) -> BrowserHistoryMigrationError {
        let primaryResult = result & 0xFF
        if primaryResult == SQLITE_BUSY || primaryResult == SQLITE_LOCKED {
            return .databaseBusy
        }
        return .unrecognizedDatabase
    }
}
