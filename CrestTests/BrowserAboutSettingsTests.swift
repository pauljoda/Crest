import Foundation
import XCTest

@testable import Crest

final class BrowserAboutSettingsTests: XCTestCase {
    func testBuildInformationReadsTheShippedBundleKeys() {
        let information = BrowserAboutBuildInformation(
            infoDictionary: [
                "CFBundleShortVersionString": "0.4.69",
                "CFBundleVersion": "123",
            ],
            bundleIdentifier: "com.example.crest"
        )

        XCTAssertEqual(information.version, "0.4.69")
        XCTAssertEqual(information.build, "123")
        XCTAssertEqual(information.bundleIdentifier, "com.example.crest")
    }

    func testBuildInformationKeepsUsefulFallbacksForIncompleteBundles() {
        let information = BrowserAboutBuildInformation(
            infoDictionary: [:],
            bundleIdentifier: nil
        )

        XCTAssertEqual(information.version, "—")
        XCTAssertEqual(information.build, "—")
        XCTAssertEqual(
            information.bundleIdentifier,
            ProductIdentity.bundleIdentifier
        )
    }

    func testAboutLinksUseThePublicSupportRoutes() {
        XCTAssertEqual(
            BrowserAboutLinks.feedback.absoluteString,
            "https://www.reddit.com/r/CrestBrowser"
        )
        XCTAssertEqual(
            BrowserAboutLinks.issues.absoluteString,
            "https://github.com/pauljoda/Crest/issues/new/choose"
        )
        XCTAssertEqual(
            BrowserAboutLinks.roadmap.absoluteString,
            "https://github.com/users/pauljoda/projects/3"
        )
    }

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

    @MainActor
    func testWhatsNewStartsCollapsed() {
        XCTAssertFalse(BrowserAboutSettingsPane.startsWhatsNewExpanded)
    }
}
