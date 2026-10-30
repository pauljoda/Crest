import XCTest

@testable import Crest

/// What's New lists the catalog's newest public entries, which only its order records.
final class BrowserAboutReleaseNotesTests: XCTestCase {
    // MARK: - Actions - Order

    func testHighlightsFollowCatalogOrderNotIdentifierOrder() throws {
        let limit = BrowserAboutReleaseNotes.highlightLimit
        // Ids run backwards alphabetically so an id sort would invert the chronology.
        let ids = (0..<(limit + 2)).map { index in
            "entry-\(Character(UnicodeScalar(UInt8(ascii: "z") - UInt8(index))))"
        }
        let objects = ids.enumerated().map { index, id in
            let category = index == ids.count - 1 ? "internal" : "fixed"
            return "\"\(id)\": {\"category\": \"\(category)\", \"message\": \"Note \\\"\(index)\\\"\"}"
        }
        let catalog = Data(
            """
            {"schemaVersion": 2, "publicationBaselines": {"stable": "\(ids[0])"},
             "entries": {\(objects.joined(separator: ",\n"))}}
            """.utf8)

        let notes = try BrowserAboutReleaseNotes(data: catalog)

        XCTAssertEqual(notes.entries.map(\.id), ids)
        XCTAssertEqual(notes.entries.first?.message, "Note \"0\"")
        XCTAssertEqual(
            notes.currentHighlights.map(\.id),
            Array(ids.dropLast().suffix(limit).reversed()),
            "the newest public entries, newest first, skipping internal ones"
        )
    }
}
