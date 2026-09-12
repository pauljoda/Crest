import Foundation
import XCTest

@testable import Crest

final class BrowserAboutSettingsTests: XCTestCase {

    func testCurrentHighlightsHideInternalEntriesAndPreferNewestIDs() throws {
        let data = try XCTUnwrap(
            """
            {
              "entries": {
                "2026-08-21-public": {
                  "category": "fixed",
                  "message": "Older public change"
                },
                "2026-08-23-internal": {
                  "category": "internal",
                  "message": "Private implementation detail"
                },
                "2026-08-22-public": {
                  "category": "new",
                  "message": "Newer public change"
                }
              }
            }
            """.data(using: .utf8)
        )

        let highlights = try BrowserAboutReleaseNotes(data: data)
            .currentHighlights(limit: 2)

        XCTAssertEqual(
            highlights.map(\.id),
            ["2026-08-22-public", "2026-08-21-public"]
        )
        XCTAssertFalse(highlights.contains { $0.category == .internal })
    }

    func testCurrentHighlightsRespectTheDisplayLimit() {
        let entries = (0..<20).map { index in
            BrowserAboutReleaseNote(
                id: String(format: "2026-08-23-%02d", index),
                category: .improved,
                message: "Change \(index)"
            )
        }

        XCTAssertEqual(
            BrowserAboutReleaseNotes(entries: entries)
                .currentHighlights(limit: 12).count,
            12
        )
        XCTAssertTrue(
            BrowserAboutReleaseNotes(entries: entries)
                .currentHighlights(limit: 0).isEmpty)
    }

}
