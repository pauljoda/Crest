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

    func testExtensionCommandsRemainScopedToTheSelectedSpace() throws {
        let fixture = makeFixture()
        let spaces = fixture.browser.session.spaces
        let firstSpace = try XCTUnwrap(spaces.first)
        let secondSpace = try XCTUnwrap(spaces.last)
        fixture.extensions.commandsBySpace = [
            firstSpace.id: [
                extensionCommand(
                    extensionID: "first.extension",
                    commandID: "open-first",
                    title: "Open First"
                )
            ],
            secondSpace.id: [
                extensionCommand(
                    extensionID: "second.extension",
                    commandID: "open-second",
                    title: "Open Second"
                )
            ],
        ]

        XCTAssertEqual(
            fixture.model.extensionCommandGroups.flatMap(\.commands)
                .map(\.extensionID),
            ["first.extension"]
        )

        fixture.model.selectedExtensionSpaceID = secondSpace.id

        let selectedCommand = try XCTUnwrap(
            fixture.model.extensionCommandGroups.first?.commands.first
        )
        XCTAssertEqual(selectedCommand.extensionID, "second.extension")

        let shortcut = BrowserShortcut(
            key: .character("h"),
            modifiers: [.option]
        )
        fixture.model.record(
            shortcut,
            for: selectedCommand,
            in: secondSpace.id
        )

        XCTAssertEqual(
            fixture.extensions.setRequests,
            [
                ExtensionSetRequest(
                    shortcut: shortcut,
                    commandID: "open-second",
                    extensionID: "second.extension",
                    spaceID: secondSpace.id
                )
            ]
        )
    }

    func testSelectedExtensionSpaceRemainsBoundByIDAfterSpaceReordering()
        throws
    {
        let fixture = makeFixture()
        let spaces = fixture.browser.session.spaces
        let selectedSpace = try XCTUnwrap(spaces.last)
        let selectedIndex = try XCTUnwrap(
            spaces.firstIndex { $0.id == selectedSpace.id }
        )
        fixture.extensions.commandsBySpace[selectedSpace.id] = [
            extensionCommand(
                extensionID: "selected.extension",
                commandID: "selected-command",
                title: "Selected Command"
            )
        ]
        fixture.model.selectedExtensionSpaceID = selectedSpace.id

        fixture.browser.moveSpaces(
            from: IndexSet(integer: selectedIndex),
            to: fixture.browser.session.spaces.startIndex
        )

        XCTAssertEqual(
            fixture.model.selectedExtensionSpaceID,
            selectedSpace.id
        )
        XCTAssertEqual(
            fixture.model.extensionCommandGroups.first?.spaceID,
            selectedSpace.id
        )
        XCTAssertEqual(
            fixture.model.extensionCommandGroups.first?.commands.first?
                .extensionID,
            "selected.extension"
        )
    }

    func testDeepLinkSelectsTheRequestedSpaceClearsSearchAndPublishesScrollTarget()
        throws
    {
        let fixture = makeFixture()
        let requestedSpace = try XCTUnwrap(fixture.browser.session.spaces.last)
        fixture.model.searchText = "old query"

        fixture.model.applyDeepLink(
            requestedSpaceID: requestedSpace.id,
            extensionID: "reader.extension",
            commandID: "capture",
            revision: 7
        )

        XCTAssertEqual(
            fixture.model.selectedExtensionSpaceID,
            requestedSpace.id
        )
        XCTAssertEqual(fixture.model.searchText, "")
        XCTAssertEqual(
            fixture.model.scrollRequest,
            BrowserShortcutScrollRequest(
                revision: 7,
                targetID: BrowserShortcutExtensionCommandID(
                    extensionID: "reader.extension",
                    commandID: "capture"
                )
            )
        )
        XCTAssertEqual(
            fixture.model.scrollRequest?.targetID.rawValue,
            "reader.extension.capture"
        )
        fixture.model.searchText = "Split"
        fixture.model.applyDeepLink(
            requestedSpaceID: requestedSpace.id, extensionID: "reader.extension", commandID: "capture", revision: 7)
        XCTAssertEqual(fixture.model.searchText, "Split", "Remounting must not replay a consumed route")
    }

    func testExtensionShortcutCannotReplaceACrestAssignment() throws {
        let fixture = makeFixture()
        let space = try XCTUnwrap(fixture.browser.session.spaces.first)
        let command = extensionCommand(
            extensionID: "reader.extension",
            commandID: "capture",
            title: "Capture"
        )
        let shortcut = try XCTUnwrap(
            fixture.shortcuts.shortcut(for: .newTab)
        )

        fixture.model.record(shortcut, for: command, in: space.id)

        XCTAssertEqual(
            fixture.model.validationIssue,
            .reservedByCrest(
                shortcut: shortcut,
                commands: [.newTab]
            )
        )
        XCTAssertTrue(fixture.extensions.setRequests.isEmpty)
    }

    func testUnsupportedExtensionShortcutReportsInvalidWithoutMutation()
        throws
    {
        let fixture = makeFixture()
        fixture.extensions.supportsShortcut = false
        let space = try XCTUnwrap(fixture.browser.session.spaces.first)
        let command = extensionCommand(
            extensionID: "reader.extension",
            commandID: "capture",
            title: "Capture"
        )

        fixture.model.record(
            BrowserShortcut(key: .special(.f20), modifiers: [.command]),
            for: command,
            in: space.id
        )

        XCTAssertEqual(fixture.model.validationIssue, .invalidShortcut)
        XCTAssertTrue(fixture.extensions.setRequests.isEmpty)
    }

    private func makeFixture(
        searchProvider: any BrowserShortcutSearchProviding = SearchProvider()
    ) -> Fixture {
        let browser = BrowserStore.preview()
        let persistence = ShortcutPersistence()
        let shortcuts = BrowserShortcutStore(persistence: persistence)
        let extensions = ExtensionCommands()
        let model = BrowserShortcutSettingsModel(
            shortcuts: shortcuts,
            browser: browser,
            extensionCommands: extensions,
            searchProvider: searchProvider,
            selectedExtensionSpaceID: browser.session.selectedSpaceID
        )
        return Fixture(
            browser: browser,
            shortcuts: shortcuts,
            extensions: extensions,
            model: model
        )
    }

    private func extensionCommand(
        extensionID: String,
        commandID: String,
        title: String
    ) -> BrowserShortcutExtensionCommand {
        BrowserShortcutExtensionCommand(
            extensionID: extensionID,
            extensionDisplayName: extensionID,
            commandID: commandID,
            title: title,
            shortcut: nil,
            isCustomized: false
        )
    }

    private struct Fixture {
        let browser: BrowserStore
        let shortcuts: BrowserShortcutStore
        let extensions: ExtensionCommands
        let model: BrowserShortcutSettingsModel
    }

    private final class ShortcutPersistence: BrowserShortcutPersisting {
        var overrides: [String: BrowserShortcutOverride]?

        func load() -> [String: BrowserShortcutOverride]? {
            overrides
        }

        func save(_ overrides: [String: BrowserShortcutOverride]) {
            self.overrides = overrides
        }

        func remove() {
            overrides = nil
        }
    }

    private final class ExtensionCommands:
        BrowserShortcutExtensionCommandManaging
    {
        var commandsBySpace: [SpaceID: [BrowserShortcutExtensionCommand]] = [:]
        var setRequests: [ExtensionSetRequest] = []
        var resetRequests: [ExtensionResetRequest] = []
        var supportsShortcut = true

        func commands(
            in spaceID: SpaceID
        ) -> [BrowserShortcutExtensionCommand] {
            commandsBySpace[spaceID] ?? []
        }

        func supports(_ shortcut: BrowserShortcut) -> Bool {
            shortcut.isValid && supportsShortcut
        }

        func setShortcut(
            _ shortcut: BrowserShortcut?,
            commandID: String,
            extensionID: String,
            in spaceID: SpaceID
        ) {
            setRequests.append(
                ExtensionSetRequest(
                    shortcut: shortcut,
                    commandID: commandID,
                    extensionID: extensionID,
                    spaceID: spaceID
                )
            )
        }

        func resetShortcut(
            commandID: String,
            extensionID: String,
            in spaceID: SpaceID
        ) {
            resetRequests.append(
                ExtensionResetRequest(
                    commandID: commandID,
                    extensionID: extensionID,
                    spaceID: spaceID
                )
            )
        }
    }

    private struct SearchProvider: BrowserShortcutSearchProviding {
        func matches(
            _ command: BrowserShortcutCommand,
            currentShortcut _: BrowserShortcut?,
            query: String
        ) -> Bool {
            query.isEmpty
                || command.rawValue.localizedCaseInsensitiveContains(query)
        }

        func matches(
            _ command: BrowserShortcutExtensionCommand,
            query: String
        ) -> Bool {
            query.isEmpty
                || command.title.localizedCaseInsensitiveContains(query)
        }
    }

    private struct ExtensionSetRequest: Equatable {
        let shortcut: BrowserShortcut?
        let commandID: String
        let extensionID: String
        let spaceID: SpaceID
    }

    private struct ExtensionResetRequest: Equatable {
        let commandID: String
        let extensionID: String
        let spaceID: SpaceID
    }
}
