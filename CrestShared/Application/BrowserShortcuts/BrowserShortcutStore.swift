import Observation

/// The person's shortcut overrides and the live chords the core resolves from
/// them. The core owns the catalog, conflicts and the override rules; this
/// store persists the overrides and keeps the resolved table for dispatch.
@Observable
@MainActor
final class BrowserShortcutStore {
    private var overrides: [String: BrowserShortcutOverride]
    private var bindings: [BrowserShortcutCommand: BrowserShortcut]
    @ObservationIgnored private let persistence: any BrowserShortcutPersisting

    init(
        persistence: any BrowserShortcutPersisting,
        reset: Bool = false
    ) {
        self.persistence = persistence
        if reset {
            persistence.remove()
        }
        let overrides = persistence.load() ?? [:]
        self.overrides = overrides
        bindings = Self.resolve(overrides)
    }

    var hasCustomizations: Bool {
        !overrides.isEmpty
    }

    func shortcut(for command: BrowserShortcutCommand) -> BrowserShortcut? {
        bindings[command]
    }

    func isCustomized(_ command: BrowserShortcutCommand) -> Bool {
        overrides[command.rawValue] != nil
    }

    func commands(
        assignedTo shortcut: BrowserShortcut
    ) -> [BrowserShortcutCommand] {
        BrowserShortcutCommand.userFacingCases.filter {
            bindings[$0] == shortcut
        }
    }

    func assign(
        _ shortcut: BrowserShortcut,
        to command: BrowserShortcutCommand,
        replacingConflicts: Bool = false
    ) -> BrowserShortcutAssignmentResult {
        let answer = BrowserCorePolicy.assignShortcut(
            shortcut,
            to: command,
            replacingConflicts: replacingConflicts,
            overrides: overrides,
            commands: BrowserShortcutCommand.userFacingCases
        )
        if let revised = answer.overrides { save(revised) }
        return answer.result
    }

    func clearShortcut(for command: BrowserShortcutCommand) {
        let answer = BrowserCorePolicy.assignShortcut(
            nil,
            to: command,
            replacingConflicts: false,
            overrides: overrides,
            commands: BrowserShortcutCommand.userFacingCases
        )
        if let revised = answer.overrides { save(revised) }
    }

    func reset(_ command: BrowserShortcutCommand) {
        var revised = overrides
        revised.removeValue(forKey: command.rawValue)
        save(revised)
    }

    func resetAll() {
        guard !overrides.isEmpty else { return }
        overrides = [:]
        bindings = Self.resolve([:])
        persistence.remove()
    }

    private static func resolve(
        _ overrides: [String: BrowserShortcutOverride]
    ) -> [BrowserShortcutCommand: BrowserShortcut] {
        BrowserCorePolicy.shortcutBindings(
            overrides: overrides,
            commands: BrowserShortcutCommand.userFacingCases
        )?.shortcuts ?? [:]
    }

    private func save(_ revised: [String: BrowserShortcutOverride]) {
        guard revised != overrides else { return }
        overrides = revised
        bindings = Self.resolve(revised)
        guard !revised.isEmpty else {
            persistence.remove()
            return
        }
        persistence.save(revised)
    }
}
