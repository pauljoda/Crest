import XCTest

@testable import Crest

@MainActor
final class BrowserShortcutSettingsModelTests: XCTestCase {
    func testCrestConflictWaitsForConfirmationBeforeReplacingAssignments() {
        let fixture = makeFixture()
        let shortcut = BrowserShortcut(
            key: .character("g"),
            modifiers: [.command, .shift]
        )
        XCTAssertEqual(
            fixture.shortcuts.assign(shortcut, to: .newTab),
            .assigned
        )

        fixture.model.record(shortcut, for: .newWindow)

        XCTAssertEqual(
            fixture.model.pendingConflict,
            BrowserShortcutPendingConflict(
                command: .newWindow,
                shortcut: shortcut,
                conflictingCommands: [.newTab]
            )
        )
        XCTAssertEqual(
            fixture.shortcuts.shortcut(for: .newTab),
            shortcut
        )

        fixture.model.replacePendingConflict()

        XCTAssertNil(fixture.shortcuts.shortcut(for: .newTab))
        XCTAssertEqual(
            fixture.shortcuts.shortcut(for: .newWindow),
            shortcut
        )
        XCTAssertNil(fixture.model.pendingConflict)
    }

    func testCancelingCrestConflictPreservesBothExistingAssignments() {
        let fixture = makeFixture()
        let shortcut = BrowserShortcut(
            key: .character("g"),
            modifiers: [.command, .shift]
        )
        XCTAssertEqual(
            fixture.shortcuts.assign(shortcut, to: .newTab),
            .assigned
        )

        fixture.model.record(shortcut, for: .newWindow)
        fixture.model.cancelPendingConflict()

        XCTAssertEqual(fixture.shortcuts.shortcut(for: .newTab), shortcut)
        XCTAssertEqual(
            fixture.shortcuts.shortcut(for: .newWindow),
            BrowserShortcutCommand.newWindow.defaultShortcut
        )
        XCTAssertNil(fixture.model.pendingConflict)
    }

    private func makeFixture() -> (shortcuts: BrowserShortcutStore, model: BrowserShortcutSettingsModel) {
        let shortcuts = BrowserShortcutStore(persistence: ShortcutPersistence())
        let model = BrowserShortcutSettingsModel(shortcuts: shortcuts, browser: .preview(), searchProvider: SearchProvider())
        return (shortcuts, model)
    }
    private final class ShortcutPersistence: BrowserShortcutPersisting {
        var overrides: [String: BrowserShortcutOverride]?
        func load() -> [String: BrowserShortcutOverride]? { overrides }
        func save(_ overrides: [String: BrowserShortcutOverride]) { self.overrides = overrides }
        func remove() { overrides = nil }
    }
    private struct SearchProvider: BrowserShortcutSearchProviding {
        func matches(_ command: BrowserShortcutCommand, currentShortcut: BrowserShortcut?, query: String) -> Bool {
            query.isEmpty || command.rawValue.localizedCaseInsensitiveContains(query)
        }
    }
}
