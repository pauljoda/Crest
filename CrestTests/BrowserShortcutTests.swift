import XCTest

@testable import Crest

final class BrowserShortcutTests: XCTestCase {
    func testArcAlignedDefaultsCoverEverydayNavigationAndPageCommands() {
        XCTAssertEqual(BrowserShortcutCommand.newTab.defaultShortcut, shortcut("t", [.command]))
        XCTAssertEqual(BrowserShortcutCommand.newWindow.defaultShortcut, shortcut("n", [.command]))
        XCTAssertEqual(BrowserShortcutCommand.newPrivateWindow.defaultShortcut, shortcut("n", [.command, .shift]))
        XCTAssertEqual(BrowserShortcutCommand.newQuickWindow.defaultShortcut, shortcut("n", [.command, .option]))
        XCTAssertEqual(BrowserShortcutCommand.closeTabOrWindow.defaultShortcut, shortcut("w", [.command]))
        XCTAssertEqual(BrowserShortcutCommand.reopenClosedTab.defaultShortcut, shortcut("t", [.command, .shift]))
        XCTAssertEqual(BrowserShortcutCommand.toggleSelectedTabPinned.defaultShortcut, shortcut("d", [.command]))
        XCTAssertEqual(BrowserShortcutCommand.copyPageLink.defaultShortcut, shortcut("c", [.command, .shift]))
        XCTAssertEqual(
            BrowserShortcutCommand.copyPageLinkAsMarkdown.defaultShortcut,
            shortcut("c", [.command, .option, .shift])
        )
        XCTAssertEqual(BrowserShortcutCommand.openLocation.defaultShortcut, shortcut("l", [.command]))
        XCTAssertEqual(BrowserShortcutCommand.toggleSidebar.defaultShortcut, shortcut("s", [.command]))
        XCTAssertEqual(BrowserShortcutCommand.clearUnpinnedTabs.defaultShortcut, shortcut("k", [.command, .shift]))
        XCTAssertEqual(BrowserShortcutCommand.mostRecentTab.defaultShortcut, special(.tab, [.control]))
        XCTAssertEqual(BrowserShortcutCommand.showHistory.defaultShortcut, shortcut("y", [.command]))
        XCTAssertEqual(BrowserShortcutCommand.reloadPage.defaultShortcut, shortcut("r", [.command]))
        XCTAssertEqual(
            BrowserShortcutCommand.reloadFromOrigin.defaultShortcut,
            shortcut("r", [.command, .shift])
        )
        XCTAssertNil(BrowserShortcutCommand.toggleReaderMode.defaultShortcut)
        XCTAssertEqual(BrowserShortcutCommand.findInPage.defaultShortcut, shortcut("f", [.command]))
        XCTAssertEqual(BrowserShortcutCommand.selectTab1.defaultShortcut, shortcut("1", [.command]))
        XCTAssertEqual(BrowserShortcutCommand.selectSpace1.defaultShortcut, shortcut("1", [.control]))
    }

    func testDefaultShortcutCatalogContainsNoDuplicateChords() {
        let assignments = Dictionary(grouping: BrowserShortcutCommand.allCases) {
            $0.defaultShortcut
        }
        let duplicateAssignments = assignments.compactMap { shortcut, commands -> [BrowserShortcutCommand]? in
            guard shortcut != nil, commands.count > 1 else { return nil }
            return commands
        }

        XCTAssertTrue(duplicateAssignments.isEmpty)
    }

    func testShortcutRequiresAtLeastOneSupportedModifier() {
        XCTAssertFalse(shortcut("t", []).isValid)
        XCTAssertTrue(shortcut("t", [.command]).isValid)
        XCTAssertTrue(special(.leftArrow, [.control, .option]).isValid)
    }

    @MainActor
    func testConflictingAssignmentDoesNotMutateUntilReplacementIsConfirmed() {
        let store = BrowserShortcutStore.inMemory()
        let replacement = shortcut("g", [.command, .shift])

        XCTAssertEqual(store.assign(replacement, to: .newTab), .assigned)
        XCTAssertEqual(
            store.assign(replacement, to: .newWindow),
            .conflict(commands: [.newTab])
        )
        XCTAssertEqual(store.shortcut(for: .newTab), replacement)
        XCTAssertEqual(
            store.shortcut(for: .newWindow),
            BrowserShortcutCommand.newWindow.defaultShortcut
        )

        XCTAssertEqual(
            store.assign(replacement, to: .newWindow, replacingConflicts: true),
            .assigned
        )
        XCTAssertNil(store.shortcut(for: .newTab))
        XCTAssertEqual(store.shortcut(for: .newWindow), replacement)
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
            BrowserShortcutCommand.newTab.defaultShortcut
        )
        XCTAssertNil(restored.shortcut(for: .showHistory))

        restored.resetAll()
        XCTAssertEqual(
            restored.shortcut(for: .showHistory),
            BrowserShortcutCommand.showHistory.defaultShortcut
        )
        XCTAssertFalse(restored.hasCustomizations)
        XCTAssertNil(persistence.overrides)
    }

    func testShortcutCatalogSearchMatchesFeatureNamesAndSpokenChords() {
        XCTAssertTrue(BrowserShortcutCommand.copyPageLink.matches(search: "copy url"))
        XCTAssertTrue(BrowserShortcutCommand.copyPageLink.matches(search: "command shift c"))
        XCTAssertTrue(BrowserShortcutCommand.previousSpace.matches(search: "option left arrow"))
        XCTAssertFalse(BrowserShortcutCommand.newWindow.matches(search: "markdown"))
    }

    @MainActor
    func testClearingAShortcutKeepsItsCommandAvailable() {
        let store = BrowserShortcutStore.inMemory()

        store.clearShortcut(for: .newTab)

        XCTAssertNil(store.shortcut(for: .newTab))
        XCTAssertTrue(store.commands(matching: "").contains(.newTab))
    }

    @MainActor
    func testShortcutCatalogExposesWebInspector() {
        let store = BrowserShortcutStore.inMemory()

        XCTAssertTrue(
            store.commands(matching: "").contains(.showWebInspector)
        )
        XCTAssertEqual(
            store.shortcut(for: .showWebInspector),
            shortcut("i", [.command, .option])
        )
        XCTAssertEqual(
            store.commands(matching: "developer"),
            [.showWebInspector]
        )
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
            BrowserShortcutCommand.newTab.defaultShortcut
        )
    }

    func testEveryCommandRawValueAndDefaultChordRemainStable() {
        XCTAssertEqual(
            BrowserShortcutCommand.allCases.map {
                "\($0.rawValue)=\(contractDescription($0.defaultShortcut))"
            },
            [
                "newWindow=character:n:1",
                "newTab=character:t:1",
                "newQuickWindow=character:n:3",
                "newPrivateWindow=character:n:9",
                "closeTabOrWindow=character:w:1",
                "closeWindow=character:w:9",
                "openLocation=character:l:1",
                "back=character:[:1",
                "forward=character:]:1",
                "reloadPage=character:r:1",
                "stopLoading=character:.:1",
                "reloadFromOrigin=character:r:9",
                "toggleSelectedTabPinned=character:d:1",
                "duplicateTab=unassigned",
                "reopenClosedTab=character:t:9",
                "clearUnpinnedTabs=character:k:9",
                "archiveTab=character:e:1",
                "previousTab=special:upArrow:3",
                "nextTab=special:downArrow:3",
                "mostRecentTab=special:tab:4",
                "selectTab1=character:1:1",
                "selectTab2=character:2:1",
                "selectTab3=character:3:1",
                "selectTab4=character:4:1",
                "selectTab5=character:5:1",
                "selectTab6=character:6:1",
                "selectTab7=character:7:1",
                "selectTab8=character:8:1",
                "selectTab9=character:9:1",
                "previousSpace=special:leftArrow:3",
                "nextSpace=special:rightArrow:3",
                "selectSpace1=character:1:4",
                "selectSpace2=character:2:4",
                "selectSpace3=character:3:4",
                "selectSpace4=character:4:4",
                "selectSpace5=character:5:4",
                "selectSpace6=character:6:4",
                "selectSpace7=character:7:4",
                "selectSpace8=character:8:4",
                "selectSpace9=character:9:4",
                "toggleReaderMode=unassigned",
                "toggleContentBlocking=unassigned",
                "findInPage=character:f:1",
                "zoomIn=character:+:1",
                "zoomOut=character:-:1",
                "actualSize=character:0:1",
                "copyPageLink=character:c:9",
                "copyPageLinkAsMarkdown=character:c:11",
                "sharePage=unassigned",
                "exportPDF=unassigned",
                "saveWebArchive=unassigned",
                "printPage=character:p:1",
                "toggleSidebar=character:s:1",
                "showHistory=character:y:1",
                "showArchive=unassigned",
                "showDownloads=character:j:9",
                "webInspectorInstructions=character:i:3",
                "splitWithNextTab=unassigned",
                "focusNextSplitCard=special:rightArrow:5",
                "focusPreviousSplitCard=special:leftArrow:5",
                "removeTabFromSplit=unassigned",
                "separateSplitTabs=character:u:3",
                "moveSplitCardLeft=special:leftArrow:9",
                "moveSplitCardRight=special:rightArrow:9",
            ]
        )
    }

    func testSplitViewDefaultsTakeTheArrowAndUnsplitChordsZenUses() {
        XCTAssertEqual(
            BrowserShortcutCommand.focusNextSplitCard.defaultShortcut,
            special(.rightArrow, [.control, .command])
        )
        XCTAssertEqual(
            BrowserShortcutCommand.focusPreviousSplitCard.defaultShortcut,
            special(.leftArrow, [.control, .command])
        )
        XCTAssertEqual(
            BrowserShortcutCommand.separateSplitTabs.defaultShortcut,
            shortcut("u", [.command, .option])
        )
        XCTAssertNil(BrowserShortcutCommand.splitWithNextTab.defaultShortcut)
        XCTAssertNil(BrowserShortcutCommand.removeTabFromSplit.defaultShortcut)
    }

    /// ⇧⌘ arrows are the last free pair: ⌥⌘ arrows switch Spaces and tabs, and
    /// ⌃⌘ arrows move focus between cards.
    func testMovingASplitCardTakesTheRemainingFreeArrowPair() {
        XCTAssertEqual(
            BrowserShortcutCommand.moveSplitCardLeft.defaultShortcut,
            special(.leftArrow, [.command, .shift])
        )
        XCTAssertEqual(
            BrowserShortcutCommand.moveSplitCardRight.defaultShortcut,
            special(.rightArrow, [.command, .shift])
        )
        let arrowChords = BrowserShortcutCommand.allCases.compactMap {
            command -> BrowserShortcut? in
            guard case .special(let key)? = command.defaultShortcut?.key,
                key == .leftArrow || key == .rightArrow
            else { return nil }
            return command.defaultShortcut
        }
        XCTAssertEqual(
            arrowChords.count,
            Set(arrowChords).count,
            "Every horizontal-arrow default has to be a distinct chord."
        )
    }

    func testSplitViewCommandsJoinTheTabsSectionAndStaySearchable() {
        for command: BrowserShortcutCommand in [
            .splitWithNextTab,
            .focusNextSplitCard,
            .focusPreviousSplitCard,
            .removeTabFromSplit,
            .separateSplitTabs,
            .moveSplitCardLeft,
            .moveSplitCardRight,
        ] {
            XCTAssertEqual(command.section, .tabs, "\(command.rawValue)")
            XCTAssertTrue(
                command.matches(search: "split"),
                "\(command.rawValue) should answer a 'split' search."
            )
        }
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
        _ modifiers: BrowserShortcutModifiers
    ) -> BrowserShortcut {
        BrowserShortcut(key: .character(character), modifiers: modifiers)
    }

    private func special(
        _ key: BrowserShortcutSpecialKey,
        _ modifiers: BrowserShortcutModifiers
    ) -> BrowserShortcut {
        BrowserShortcut(key: .special(key), modifiers: modifiers)
    }

    private func contractDescription(_ shortcut: BrowserShortcut?) -> String {
        guard let shortcut else { return "unassigned" }
        let key: String
        switch shortcut.key {
        case .character(let character):
            key = "character:\(character)"
        case .special(let specialKey):
            key = "special:\(specialKey.rawValue)"
        }
        return "\(key):\(shortcut.modifiers.rawValue)"
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
}
