import Foundation

/// What a numbered selection command reaches: the zero-based position of a
/// tab in sidebar order, or of a Space.
enum BrowserNumberedSelection: Equatable, Sendable {
    case tab(Int)
    case space(Int)
}

/// Shortcut rules owned by the portable core: how overrides resolve against
/// the catalog, conflicts, and what the numbered commands select. Search for
/// the settings list stays native. A chord crosses in `BrowserShortcut`'s own
/// coded shape, which is also the core's wire and persisted shape.
extension BrowserCorePolicy {
    // MARK: - Types

    private struct BindingsRequest: Encodable {
        let platform: DevicePlatform
        let commands: [ShortcutCommand]
        /// A command left unassigned crosses as `null`.
        let overrides: [String: BrowserShortcut?]
    }

    private struct BindingsAnswer: Decodable {
        struct Binding: Decodable {
            let command: ShortcutCommand
            @BrowserCoreOptional var shortcut: BrowserShortcut?
        }

        let bindings: [Binding]
    }

    private struct AssignRequest: Encodable {
        let platform: DevicePlatform
        let commands: [ShortcutCommand]
        let overrides: [String: BrowserShortcut?]
        let command: ShortcutCommand
        @BrowserCoreNullable var shortcut: BrowserShortcut?
        let replacingConflicts: Bool
    }

    private struct AssignAnswer: Decodable {
        /// Raw values are the core's assignment result spellings.
        enum Result: String, Decodable {
            case assigned
            case conflict
            case invalid
        }

        let result: Result
        @BrowserCoreOptional var overrides: [String: BrowserShortcut?]?
        @BrowserCoreOptional var conflicts: BrowserCoreKnownValues<ShortcutCommand>?
    }

    private struct NumberedSelectionRequest: Encodable {
        let tabCount: Int
        let spaceCount: Int
    }

    private struct NumberedSelectionAnswer: Decodable {
        struct Selection: Decodable {
            /// Raw values are the core's numbered selection target spellings.
            enum Target: String, Decodable {
                case tab
                case space
            }

            @BrowserCoreOptional var command: ShortcutCommand?
            @BrowserCoreOptional var index: Int?
            @BrowserCoreOptional var target: Target?
        }

        let selections: [Selection]
    }

    // MARK: - Actions - Shortcuts

    /// Live chords for `commands`. Nil when the core cannot answer; the caller
    /// then binds nothing rather than guessing.
    static func shortcutBindings(
        overrides: [String: BrowserShortcutOverride],
        commands: [ShortcutCommand]
    ) -> [ShortcutCommand: BrowserShortcut]? {
        let request = BindingsRequest(platform: devicePlatform, commands: commands, overrides: coreOverrides(overrides))
        guard let answer = evaluate(.shortcutsBindings, request, answer: BindingsAnswer.self) else { return nil }
        var bindings: [ShortcutCommand: BrowserShortcut] = [:]
        for binding in answer.bindings {
            if let shortcut = binding.shortcut { bindings[binding.command] = shortcut }
        }
        return bindings
    }

    /// Binds `shortcut` to `command`, or clears it when `shortcut` is nil, and
    /// returns the revised overrides when the binding applies. A core that
    /// cannot answer reports a conflict, so nothing is ever bound twice.
    static func assignShortcut(
        _ shortcut: BrowserShortcut?, to command: ShortcutCommand,
        replacingConflicts: Bool, overrides: [String: BrowserShortcutOverride], commands: [ShortcutCommand]
    ) -> (result: BrowserShortcutAssignmentResult, overrides: [String: BrowserShortcutOverride]?) {
        let unavailable: (BrowserShortcutAssignmentResult, [String: BrowserShortcutOverride]?) = (
            .conflict(commands: []), nil
        )
        let request = AssignRequest(
            platform: devicePlatform, commands: commands, overrides: coreOverrides(overrides), command: command,
            shortcut: shortcut, replacingConflicts: replacingConflicts)
        guard let answer = evaluate(.shortcutsAssign, request, answer: AssignAnswer.self) else { return unavailable }
        switch answer.result {
        case .assigned:
            guard let revised = answer.overrides else { return unavailable }
            return (.assigned, revised.mapValues { $0.map(BrowserShortcutOverride.custom) ?? .unassigned })
        case .invalid:
            return (.invalid, nil)
        case .conflict:
            return (.conflict(commands: answer.conflicts?.values ?? []), nil)
        }
    }

    /// Where each numbered selection command leads for these counts. A command
    /// with nowhere to go is absent, and so is every command when the core
    /// cannot answer.
    static func numberedSelections(tabCount: Int, spaceCount: Int) -> [ShortcutCommand: BrowserNumberedSelection]
    {
        let request = NumberedSelectionRequest(tabCount: tabCount, spaceCount: spaceCount)
        guard let answer = evaluate(.shortcutsNumberedSelection, request, answer: NumberedSelectionAnswer.self) else {
            return [:]
        }
        var selections: [ShortcutCommand: BrowserNumberedSelection] = [:]
        for selection in answer.selections {
            guard let command = selection.command, let index = selection.index else { continue }
            selections[command] = selection.target == .space ? .space(index) : .tab(index)
        }
        return selections
    }

    private static func coreOverrides(_ overrides: [String: BrowserShortcutOverride]) -> [String: BrowserShortcut?] {
        overrides.mapValues { value in
            switch value {
            case .custom(let shortcut): shortcut
            case .unassigned: nil
            }
        }
    }
}
