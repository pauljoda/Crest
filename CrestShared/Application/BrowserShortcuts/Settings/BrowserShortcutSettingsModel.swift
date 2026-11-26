import Foundation
import Observation

@Observable
@MainActor
final class BrowserShortcutSettingsModel {
    private let shortcuts: BrowserShortcutStore

    var searchText = ""
    var validationIssue: BrowserShortcutValidationIssue?
    var pendingConflict: BrowserShortcutPendingConflict?

    @ObservationIgnored private var searchProvider: any BrowserShortcutSearchProviding
    @ObservationIgnored private var cachedGroupsQuery: String?
    @ObservationIgnored private var cachedGroupsLocaleCount = 0
    @ObservationIgnored private var cachedGroupsRevision = 0
    @ObservationIgnored private var cachedGroups: [BrowserShortcutCommandGroup]?

    init(
        shortcuts: BrowserShortcutStore,
        searchProvider: any BrowserShortcutSearchProviding
    ) {
        self.shortcuts = shortcuts
        self.searchProvider = searchProvider
    }

    var isPresentingConflict: Bool {
        get { pendingConflict != nil }
        set {
            if !newValue {
                pendingConflict = nil
            }
        }
    }

    var hasCrestCustomizations: Bool {
        shortcuts.hasCustomizations
    }

    func shortcut(
        for command: ShortcutCommand
    ) -> BrowserShortcut? {
        shortcuts.shortcut(for: command)
    }

    func isCustomized(_ command: ShortcutCommand) -> Bool {
        shortcuts.isCustomized(command)
    }

    func preference(for command: ShortcutCommand) -> ShortcutPreference {
        shortcuts.preference(for: command)
    }

    func choosesPreference(_ command: ShortcutCommand) -> Bool {
        shortcuts.choosesPreference(command)
    }

    func choose(_ preference: ShortcutPreference, for command: ShortcutCommand) {
        shortcuts.choose(preference, for: command)
    }

    var commandGroups: [BrowserShortcutCommandGroup] {
        // Observe searchText and shortcut store changes so SwiftUI invalidates
        // when filtering or bindings change, while caching the grouped array
        // across scroll-time reads.
        let query = searchText
        let offered = shortcuts.offeredCommands
        let isCustomized = shortcuts.hasCustomizations
        let revision = offered.count &* 31 &+ (isCustomized ? 1 : 0) &+ cachedGroupsRevision
        if let cachedGroups, cachedGroupsQuery == query, cachedGroupsLocaleCount == revision {
            return cachedGroups
        }
        let matches: [ShortcutCommand]
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            matches = offered
        } else {
            matches = offered.filter {
                searchProvider.matches(
                    $0,
                    currentShortcut: shortcuts.shortcut(for: $0),
                    query: query
                )
            }
        }
        var bySection: [ShortcutSection: [ShortcutCommand]] = [:]
        for command in matches {
            bySection[command.section, default: []].append(command)
        }
        let groups = ShortcutSection.all.compactMap { section -> BrowserShortcutCommandGroup? in
            guard let commands = bySection[section], !commands.isEmpty else { return nil }
            return BrowserShortcutCommandGroup(section: section, commands: commands)
        }
        cachedGroupsQuery = query
        cachedGroupsLocaleCount = revision
        cachedGroups = groups
        return groups
    }

    func updateSearchProvider(
        _ searchProvider: any BrowserShortcutSearchProviding
    ) {
        self.searchProvider = searchProvider
        cachedGroupsRevision &+= 1
        cachedGroups = nil
    }

    func record(
        _ shortcut: BrowserShortcut?,
        for command: ShortcutCommand
    ) {
        guard let shortcut else {
            shortcuts.clearShortcut(for: command)
            validationIssue = nil
            return
        }

        shortcuts.assign(shortcut, to: command).apply(to: self, recording: shortcut, for: command)
    }

    func replacePendingConflict() {
        guard let pendingConflict else { return }
        _ = shortcuts.reassign(
            pendingConflict.shortcut,
            to: pendingConflict.command
        )
        self.pendingConflict = nil
        validationIssue = nil
    }

    func cancelPendingConflict() {
        pendingConflict = nil
    }

    func reset(_ command: ShortcutCommand) {
        shortcuts.reset(command)
        validationIssue = nil
    }

    func resetAllCrestShortcuts() {
        shortcuts.resetAll()
        validationIssue = nil
    }

    func reportInvalidShortcut() {
        validationIssue = .invalidShortcut
    }

}
