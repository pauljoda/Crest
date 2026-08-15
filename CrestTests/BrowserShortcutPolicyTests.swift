import XCTest

@testable import Crest

final class BrowserShortcutPolicyTests: XCTestCase {
    func testConflictPolicyExcludesTheCommandBeingReassigned() {
        let shortcut = BrowserShortcut(
            key: .character("g"),
            modifiers: [.command]
        )
        let assignments: [BrowserShortcutCommand: BrowserShortcut] = [
            .newTab: shortcut,
            .newWindow: shortcut,
            .showHistory: BrowserShortcut(
                key: .character("y"),
                modifiers: [.command]
            ),
        ]

        XCTAssertEqual(
            BrowserShortcutConflictPolicy.conflicts(
                assigning: shortcut,
                to: .newWindow,
                currentAssignments: assignments
            ),
            [.newTab]
        )
    }

    func testSearchPolicyRequiresEveryTermAndExactSingleCharacterTokens() {
        let fields = [
            "Copy Page Link",
            "Page",
            "copy url address clipboard",
            "command shift c",
        ]

        XCTAssertTrue(
            BrowserShortcutSearchPolicy.matches(
                query: "copy url",
                fields: fields
            )
        )
        XCTAssertTrue(
            BrowserShortcutSearchPolicy.matches(
                query: "command shift c",
                fields: fields
            )
        )
        XCTAssertFalse(
            BrowserShortcutSearchPolicy.matches(
                query: "command shift p",
                fields: fields
            )
        )
        XCTAssertTrue(
            BrowserShortcutSearchPolicy.matches(query: "", fields: fields)
        )
    }

    func testExtensionSearchPreservesSingleTrimmedPhraseContainment() {
        let fields = [
            "Reader Tools",
            "Capture Article",
            "capture",
        ]

        XCTAssertTrue(
            BrowserShortcutSearchPolicy.containsTrimmedPhrase(
                query: "  reader tools  ",
                fields: fields
            )
        )
        XCTAssertTrue(
            BrowserShortcutSearchPolicy.containsTrimmedPhrase(
                query: "CAPTURE ARTICLE",
                fields: fields
            )
        )
        XCTAssertFalse(
            BrowserShortcutSearchPolicy.containsTrimmedPhrase(
                query: "reader capture",
                fields: fields
            )
        )
        XCTAssertTrue(
            BrowserShortcutSearchPolicy.containsTrimmedPhrase(
                query: "   ",
                fields: fields
            )
        )
    }
}
