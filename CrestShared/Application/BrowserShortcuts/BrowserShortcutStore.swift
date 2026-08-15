import Observation

@Observable
@MainActor
final class BrowserShortcutStore {
    private var overrides: [String: BrowserShortcutOverride]
    @ObservationIgnored private let persistence: any BrowserShortcutPersisting

    init(
        persistence: any BrowserShortcutPersisting,
        reset: Bool = false
    ) {
        self.persistence = persistence
        if reset {
            persistence.remove()
        }
        overrides = persistence.load() ?? [:]
    }

    var hasCustomizations: Bool {
        !overrides.isEmpty
    }

    func shortcut(for command: BrowserShortcutCommand) -> BrowserShortcut? {
        switch overrides[command.rawValue] {
        case .custom(let shortcut): shortcut
        case .unassigned: nil
        case nil: command.defaultShortcut
        }
    }

    func isCustomized(_ command: BrowserShortcutCommand) -> Bool {
        overrides[command.rawValue] != nil
    }

    func commands(
        assignedTo shortcut: BrowserShortcut
    ) -> [BrowserShortcutCommand] {
        BrowserShortcutCommand.userFacingCases.filter {
            self.shortcut(for: $0) == shortcut
        }
    }

    func assign(
        _ shortcut: BrowserShortcut,
        to command: BrowserShortcutCommand,
        replacingConflicts: Bool = false
    ) -> BrowserShortcutAssignmentResult {
        guard shortcut.isValid else { return .invalid }
        let conflicts = BrowserShortcutConflictPolicy.conflicts(
            assigning: shortcut,
            to: command,
            currentAssignments: currentAssignments
        )
        guard conflicts.isEmpty || replacingConflicts else {
            return .conflict(commands: conflicts)
        }

        var revised = overrides
        for conflict in conflicts {
            Self.set(nil, for: conflict, in: &revised)
        }
        Self.set(shortcut, for: command, in: &revised)
        save(revised)
        return .assigned
    }

    func clearShortcut(for command: BrowserShortcutCommand) {
        var revised = overrides
        Self.set(nil, for: command, in: &revised)
        save(revised)
    }

    func reset(_ command: BrowserShortcutCommand) {
        var revised = overrides
        revised.removeValue(forKey: command.rawValue)
        save(revised)
    }

    func resetAll() {
        guard !overrides.isEmpty else { return }
        overrides = [:]
        persistence.remove()
    }

    private var currentAssignments: [BrowserShortcutCommand: BrowserShortcut] {
        Dictionary(
            uniqueKeysWithValues:
                BrowserShortcutCommand.userFacingCases.compactMap { command in
                    shortcut(for: command).map { (command, $0) }
                }
        )
    }

    private static func set(
        _ shortcut: BrowserShortcut?,
        for command: BrowserShortcutCommand,
        in overrides: inout [String: BrowserShortcutOverride]
    ) {
        if shortcut == command.defaultShortcut {
            overrides.removeValue(forKey: command.rawValue)
            return
        }
        overrides[command.rawValue] =
            shortcut.map(BrowserShortcutOverride.custom)
            ?? .unassigned
    }

    private func save(_ revised: [String: BrowserShortcutOverride]) {
        guard revised != overrides else { return }
        overrides = revised
        guard !revised.isEmpty else {
            persistence.remove()
            return
        }
        persistence.save(revised)
    }
}
