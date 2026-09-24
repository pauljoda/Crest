import AppKit
import XCTest

@testable import Crest

final class BrowserShortcutTests: XCTestCase {
    @MainActor
    func testNativeDispatchUsesCurrentOverridesAndLeavesDisabledCommandsToTheResponder() throws {
        let store = BrowserShortcutStore.inMemory()
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0, context: nil,
            characters: "i", charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34))
        XCTAssertEqual(store.command(for: event, isEnabled: { _ in true }), .toggleDeveloperToolbar)
        XCTAssertNil(store.command(for: event, isEnabled: { _ in false }))
        store.clearShortcut(for: .toggleDeveloperToolbar)
        XCTAssertNil(store.command(for: event, isEnabled: { _ in true }))
        XCTAssertEqual(store.assign(BrowserShortcut(key: .character("i"), modifiers: [.command, .shift]), to: .newTab), .assigned)
        XCTAssertEqual(store.command(for: event, isEnabled: { _ in true }), .newTab)
    }

    @MainActor
    func testDefaultZoomAliasNeverOverridesAnExplicitAssignment() throws {
        let store = BrowserShortcutStore.inMemory()
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24))
        XCTAssertEqual(store.command(for: event, isEnabled: { _ in true }), .zoomIn)
        XCTAssertEqual(store.assign(BrowserShortcut(key: .character("="), modifiers: .command), to: .newTab), .assigned)
        XCTAssertEqual(store.command(for: event, isEnabled: { _ in true }), .newTab)
        XCTAssertNil(store.command(for: event, isEnabled: { $0 != .newTab }))
        store.clearShortcut(for: .newTab)
        store.clearShortcut(for: .zoomIn)
        XCTAssertNil(store.command(for: event, isEnabled: { _ in true }))
    }

    func testCommandsForAnEngineFeatureAreOfferedOnlyWhereTheEngineDeclaresIt() {
        let engineFeatures: Set<ShortcutCommand> = [
            .toggleReaderMode, .toggleContentBlocking, .toggleTranslationToolbar,
        ]
        for command in ShortcutCommand.all {
            XCTAssertTrue(command.isOffered(by: BrowserEngineRegistration.webKit), "\(command)")
            XCTAssertEqual(
                command.isOffered(by: BrowserEngineRegistration.chromium),
                !engineFeatures.contains(command), "\(command)")
        }
    }

    func testShortcutRequiresAtLeastOneSupportedModifier() {
        XCTAssertFalse(shortcut("t", []).isValid)
        XCTAssertTrue(shortcut("t", [.command]).isValid)
        XCTAssertTrue(special(.leftArrow, [.control, .option]).isValid)
    }

    @MainActor
    func testCustomAndUnassignedShortcutsPersistAndResetIndependently() {
        let persistence = InMemoryBrowserShortcutPersistence()
        let custom = shortcut("h", [.command, .option])
        var store: BrowserShortcutStore? = BrowserShortcutStore(
            persistence: persistence
        )

        XCTAssertEqual(store?.assign(custom, to: .newTab), .assigned)
        store?.clearShortcut(for: .showHistory)
        XCTAssertTrue(store?.isCustomized(.newTab) == true)
        XCTAssertTrue(store?.isCustomized(.showHistory) == true)
        store = nil

        let restored = BrowserShortcutStore(
            persistence: persistence
        )
        XCTAssertEqual(restored.shortcut(for: .newTab), custom)
        XCTAssertNil(restored.shortcut(for: .showHistory))

        restored.reset(.newTab)
        XCTAssertEqual(
            restored.shortcut(for: .newTab),
            ShortcutCommand.newTab.defaultShortcut
        )
        XCTAssertNil(restored.shortcut(for: .showHistory))

        restored.resetAll()
        XCTAssertEqual(
            restored.shortcut(for: .showHistory),
            ShortcutCommand.showHistory.defaultShortcut
        )
        XCTAssertFalse(restored.hasCustomizations)
        XCTAssertNil(persistence.overrides)
    }

    @MainActor
    func testNewWindowDefaultsYieldToPersistedCustomBindingsWithoutRewritingThem() {
        let cases: [(owner: ShortcutCommand, displaced: ShortcutCommand, chord: BrowserShortcut)] = [
            (.newQuickWindow, .newBlankWindow, shortcut("n", [.command, .option])),
            (.newTab, .newQuickWindow, shortcut("n", [.command, .option, .shift])),
        ]
        for item in cases {
            let saved: [String: BrowserShortcutOverride] = [
                item.owner.name: .custom(item.chord), ShortcutCommand.showHistory.name: .unassigned,
            ]
            let persistence = InMemoryBrowserShortcutPersistence(overrides: saved)
            let store = BrowserShortcutStore(persistence: persistence)

            XCTAssertEqual(store.shortcut(for: item.owner), item.chord)
            XCTAssertEqual(store.commands(assignedTo: item.chord), [item.owner])
            XCTAssertNil(store.shortcut(for: item.displaced))
            XCTAssertFalse(store.isCustomized(item.displaced))
            XCTAssertEqual(persistence.overrides, saved)

            store.reset(item.owner)
            XCTAssertEqual(store.shortcut(for: item.displaced), item.displaced.defaultShortcut)
            XCTAssertNil(store.shortcut(for: .showHistory))
        }
    }

    @MainActor
    func testShortcutSearchUsesCurrentBindingsAndFindsUnassignedCommands() {
        let store = BrowserShortcutStore.inMemory()
        let custom = shortcut("g", [.command, .option])
        XCTAssertEqual(store.assign(custom, to: .newTab), .assigned)

        XCTAssertEqual(store.commands(matching: "option g"), [.newTab])
        XCTAssertTrue(store.commands(matching: "unassigned").contains(.duplicateTab))
        XCTAssertFalse(store.commands(matching: "command t").contains(.newTab))
    }

    @MainActor
    func testCrestShortcutAssignmentsCanBeResolvedBeforeExtensions() throws {
        let store = BrowserShortcutStore.inMemory()
        let newTab = try XCTUnwrap(store.shortcut(for: .newTab))

        XCTAssertEqual(store.commands(assignedTo: newTab), [.newTab])
        XCTAssertTrue(store.commands(assignedTo: shortcut("g", [.option])).isEmpty)
    }

    @MainActor
    func testInMemoryStoreNeverCarriesFixtureOverridesIntoAnotherLaunch() {
        let first = BrowserShortcutStore.inMemory()
        let custom = shortcut("g", [.command, .option])

        XCTAssertEqual(first.assign(custom, to: .newTab), .assigned)
        XCTAssertEqual(first.shortcut(for: .newTab), custom)

        let nextLaunch = BrowserShortcutStore.inMemory()
        XCTAssertEqual(
            nextLaunch.shortcut(for: .newTab),
            ShortcutCommand.newTab.defaultShortcut
        )
    }

    @MainActor
    func testUserDefaultsPersistenceKeepsTheV1KeyAndJSONShape() throws {
        let testDefaults = try makeDefaults()
        defer { testDefaults.clear() }
        let store = BrowserShortcutStore(defaults: testDefaults.defaults)

        XCTAssertEqual(
            store.assign(shortcut("g", [.command, .option]), to: .newTab),
            .assigned
        )
        store.clearShortcut(for: .showHistory)

        let data = try XCTUnwrap(
            testDefaults.defaults.data(
                forKey: "crest.keyboard-shortcuts.v1"
            )
        )
        let expected = Data(
            #"{"newTab":{"custom":{"_0":{"key":{"character":"g"},"modifiers":3}}},"showHistory":{"unassigned":{}}}"#
                .utf8
        )
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: data) as? NSDictionary,
            try JSONSerialization.jsonObject(with: expected) as? NSDictionary
        )
    }

    @MainActor
    func testV1JSONRestoresLegacyOverridesAndRetainsUnknownCommandKeys()
        throws
    {
        let testDefaults = try makeDefaults()
        defer { testDefaults.clear() }
        let persistenceKey = "shortcuts"
        testDefaults.defaults.set(
            Data(
                #"{"futureCommand":{"custom":{"_0":{"key":{"special":"f20"},"modifiers":4}}},"newTab":{"custom":{"_0":{"key":{"character":"g"},"modifiers":3}}},"showHistory":{"unassigned":{}}}"#
                    .utf8
            ),
            forKey: persistenceKey
        )

        let store = BrowserShortcutStore(
            defaults: testDefaults.defaults,
            persistenceKey: persistenceKey
        )

        XCTAssertEqual(
            store.shortcut(for: .newTab),
            shortcut("g", [.command, .option])
        )
        XCTAssertNil(store.shortcut(for: .showHistory))
        XCTAssertEqual(
            store.assign(shortcut("h", [.control]), to: .newWindow),
            .assigned
        )

        let savedData = try XCTUnwrap(
            testDefaults.defaults.data(forKey: persistenceKey)
        )
        let saved = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: savedData)
                as? [String: Any]
        )
        XCTAssertNotNil(saved["futureCommand"])
    }

    private func shortcut(
        _ character: Character,
        _ modifiers: ShortcutModifiers
    ) -> BrowserShortcut {
        BrowserShortcut(key: .character(character), modifiers: modifiers)
    }

    private func special(
        _ key: ShortcutSpecialKey,
        _ modifiers: ShortcutModifiers
    ) -> BrowserShortcut {
        BrowserShortcut(key: .special(key), modifiers: modifiers)
    }

    private func makeDefaults() throws -> TestDefaults {
        let suiteName = "BrowserShortcutTests.\(UUID().uuidString)"
        return TestDefaults(
            defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)),
            suiteName: suiteName
        )
    }

    private struct TestDefaults {
        let defaults: UserDefaults
        let suiteName: String

        func clear() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @MainActor
    func testIsolatedLaunchDoesNotConstructOrUsePersistentPersistence() {
        let persistence = PersistenceSpy()
        var persistentFactoryCallCount = 0
        let store = BrowserShortcutStore.launch(
            usesIsolatedLaunch: true,
            reset: true,
            persistentPersistence: {
                persistentFactoryCallCount += 1
                return persistence
            }
        )

        XCTAssertEqual(persistentFactoryCallCount, 0)
        XCTAssertEqual(
            store.assign(
                BrowserShortcut(
                    key: .character("g"),
                    modifiers: [.command]
                ),
                to: .newTab
            ),
            .assigned
        )
        XCTAssertEqual(persistence.loadCount, 0)
        XCTAssertEqual(persistence.saveCount, 0)
        XCTAssertEqual(persistence.removeCount, 0)
    }

    @MainActor
    func testStandardLaunchUsesTheInjectedPersistentPersistence() {
        let persistence = PersistenceSpy()
        _ = BrowserShortcutStore.launch(
            usesIsolatedLaunch: false,
            reset: true,
            persistentPersistence: { persistence }
        )

        XCTAssertEqual(persistence.loadCount, 1)
        XCTAssertEqual(persistence.removeCount, 1)
    }

    private final class PersistenceSpy: BrowserShortcutPersisting {
        private(set) var loadCount = 0
        private(set) var saveCount = 0
        private(set) var removeCount = 0

        func load() -> [String: BrowserShortcutOverride]? {
            loadCount += 1
            return nil
        }

        func save(_ overrides: [String: BrowserShortcutOverride]) {
            saveCount += 1
        }

        func remove() {
            removeCount += 1
        }
    }
}
