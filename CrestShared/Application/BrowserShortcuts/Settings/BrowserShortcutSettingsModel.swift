import Foundation
import Observation

@Observable
@MainActor
final class BrowserShortcutSettingsModel {
    private let shortcuts: BrowserShortcutStore
    private let browser: BrowserStore

    var searchText = ""
    var selectedExtensionSpaceID: SpaceID?
    private(set) var validationIssue: BrowserShortcutValidationIssue?
    private(set) var pendingConflict: BrowserShortcutPendingConflict?
    private(set) var scrollRequest: BrowserShortcutScrollRequest?

    @ObservationIgnored
    private let extensionCommands: any BrowserShortcutExtensionCommandManaging
    private var searchProvider: any BrowserShortcutSearchProviding

    init(
        shortcuts: BrowserShortcutStore,
        browser: BrowserStore,
        extensionCommands: any BrowserShortcutExtensionCommandManaging,
        searchProvider: any BrowserShortcutSearchProviding,
        selectedExtensionSpaceID: SpaceID? = nil
    ) {
        self.shortcuts = shortcuts
        self.browser = browser
        self.extensionCommands = extensionCommands
        self.searchProvider = searchProvider
        self.selectedExtensionSpaceID =
            selectedExtensionSpaceID ?? browser.session.selectedSpaceID
    }

    var isPresentingConflict: Bool {
        get { pendingConflict != nil }
        set {
            if !newValue {
                pendingConflict = nil
            }
        }
    }

    var spaces: [BrowserSpace] {
        browser.session.spaces
    }

    var hasCrestCustomizations: Bool {
        shortcuts.hasCustomizations
    }

    func shortcut(
        for command: BrowserShortcutCommand
    ) -> BrowserShortcut? {
        shortcuts.shortcut(for: command)
    }

    func isCustomized(_ command: BrowserShortcutCommand) -> Bool {
        shortcuts.isCustomized(command)
    }

    var commandGroups: [BrowserShortcutCommandGroup] {
        let matches = BrowserShortcutCommand.userFacingCases.filter {
            searchProvider.matches(
                $0,
                currentShortcut: shortcuts.shortcut(for: $0),
                query: searchText
            )
        }
        return BrowserShortcutSection.allCases.compactMap { section in
            let commands = matches.filter { $0.section == section }
            guard !commands.isEmpty else { return nil }
            return BrowserShortcutCommandGroup(
                section: section,
                commands: commands
            )
        }
    }

    var extensionCommandGroups: [BrowserShortcutExtensionCommandGroup] {
        guard let spaceID = selectedExtensionSpaceID,
            let space = browser.session.space(id: spaceID)
        else {
            return []
        }
        let matchingCommands = extensionCommands.commands(in: spaceID)
            .filter { searchProvider.matches($0, query: searchText) }
        return Dictionary(grouping: matchingCommands, by: \.extensionID)
            .values
            .compactMap { commands in
                guard let first = commands.first else { return nil }
                return BrowserShortcutExtensionCommandGroup(
                    extensionID: first.extensionID,
                    extensionName: first.extensionDisplayName,
                    spaceID: spaceID,
                    spaceName: space.name,
                    commands: commands
                )
            }
            .sorted {
                $0.extensionName.localizedStandardCompare($1.extensionName)
                    == .orderedAscending
            }
    }

    func updateSearchProvider(
        _ searchProvider: any BrowserShortcutSearchProviding
    ) {
        self.searchProvider = searchProvider
    }

    func record(
        _ shortcut: BrowserShortcut?,
        for command: BrowserShortcutCommand
    ) {
        guard let shortcut else {
            shortcuts.clearShortcut(for: command)
            validationIssue = nil
            return
        }

        switch shortcuts.assign(shortcut, to: command) {
        case .assigned:
            validationIssue = nil
        case .conflict(let commands):
            pendingConflict = BrowserShortcutPendingConflict(
                command: command,
                shortcut: shortcut,
                conflictingCommands: commands
            )
        case .invalid:
            validationIssue = .invalidShortcut
        }
    }

    func record(
        _ shortcut: BrowserShortcut?,
        for command: BrowserShortcutExtensionCommand,
        in spaceID: SpaceID
    ) {
        guard let shortcut else {
            extensionCommands.setShortcut(
                nil,
                commandID: command.commandID,
                extensionID: command.extensionID,
                in: spaceID
            )
            validationIssue = nil
            return
        }
        guard extensionCommands.supports(shortcut) else {
            validationIssue = .invalidShortcut
            return
        }
        let crestConflicts = shortcuts.commands(assignedTo: shortcut)
        guard crestConflicts.isEmpty else {
            validationIssue = .reservedByCrest(
                shortcut: shortcut,
                commands: crestConflicts
            )
            return
        }
        extensionCommands.setShortcut(
            shortcut,
            commandID: command.commandID,
            extensionID: command.extensionID,
            in: spaceID
        )
        validationIssue = nil
    }

    func replacePendingConflict() {
        guard let pendingConflict else { return }
        _ = shortcuts.assign(
            pendingConflict.shortcut,
            to: pendingConflict.command,
            replacingConflicts: true
        )
        self.pendingConflict = nil
        validationIssue = nil
    }

    func cancelPendingConflict() {
        pendingConflict = nil
    }

    func reset(_ command: BrowserShortcutCommand) {
        shortcuts.reset(command)
        validationIssue = nil
    }

    func reset(
        _ command: BrowserShortcutExtensionCommand,
        in spaceID: SpaceID
    ) {
        extensionCommands.resetShortcut(
            commandID: command.commandID,
            extensionID: command.extensionID,
            in: spaceID
        )
        validationIssue = nil
    }

    func resetAllCrestShortcuts() {
        shortcuts.resetAll()
        validationIssue = nil
    }

    func reportInvalidShortcut() {
        validationIssue = .invalidShortcut
    }

    func clearValidationIssue() {
        validationIssue = nil
    }

    func applyDeepLink(
        requestedSpaceID: SpaceID?,
        extensionID: String?,
        commandID: String?,
        revision: Int
    ) {
        guard revision > 0 else { return }
        if let requestedSpaceID,
            browser.session.space(id: requestedSpaceID) != nil
        {
            selectedExtensionSpaceID = requestedSpaceID
        }
        searchText = ""
        guard let extensionID, let commandID else {
            scrollRequest = nil
            return
        }
        scrollRequest = BrowserShortcutScrollRequest(
            revision: revision,
            targetID: BrowserShortcutExtensionCommandID(
                extensionID: extensionID,
                commandID: commandID
            )
        )
    }
}
