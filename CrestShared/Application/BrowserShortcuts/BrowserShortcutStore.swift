import Observation

/// The person's shortcut overrides and the live chords the core resolves from
/// them. The core owns the catalog, conflicts and the override rules; this
/// store persists the overrides and keeps the resolved table for dispatch.
@Observable
@MainActor
final class BrowserShortcutStore {
    private var overrides: [String: BrowserShortcutOverride]
    private var bindings: [ShortcutCommand: BrowserShortcut]
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

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        bindings[command]
    }

    func isCustomized(_ command: ShortcutCommand) -> Bool {
        overrides[command.name] != nil
    }

    func commands(
        assignedTo shortcut: BrowserShortcut
    ) -> [ShortcutCommand] {
        ShortcutCommand.offered.filter {
            bindings[$0] == shortcut
        }
    }

    func assign(
        _ shortcut: BrowserShortcut,
        to command: ShortcutCommand,
        replacingConflicts: Bool = false
    ) -> BrowserShortcutAssignmentResult {
        let answer = BrowserCorePolicy.assignShortcut(
            shortcut,
            to: command,
            replacingConflicts: replacingConflicts,
            overrides: overrides,
            commands: ShortcutCommand.offered
        )
        if let revised = answer.overrides { save(revised) }
        return answer.result
    }

    func clearShortcut(for command: ShortcutCommand) {
        let answer = BrowserCorePolicy.assignShortcut(
            nil,
            to: command,
            replacingConflicts: false,
            overrides: overrides,
            commands: ShortcutCommand.offered
        )
        if let revised = answer.overrides { save(revised) }
    }

    func reset(_ command: ShortcutCommand) {
        var revised = overrides
        revised.removeValue(forKey: command.name)
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
    ) -> [ShortcutCommand: BrowserShortcut] {
        BrowserCorePolicy.shortcutBindings(
            overrides: overrides,
            commands: ShortcutCommand.offered
        ) ?? [:]
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
