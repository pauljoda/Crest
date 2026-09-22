import Foundation

/// What a numbered selection command reaches: the zero-based position of a
/// tab in sidebar order, or of a Space.
enum BrowserNumberedSelection: Equatable, Sendable {
    case tab(Int)
    case space(Int)
}

/// The live chord of every offered command and the catalog defaults, as the
/// core resolved them from the person's overrides.
struct BrowserShortcutBindings: Equatable, Sendable {
    var shortcuts: [BrowserShortcutCommand: BrowserShortcut] = [:]
    var defaults: [BrowserShortcutCommand: BrowserShortcut] = [:]
}

extension BrowserShortcut {
    /// The chord in the core's wire shape, which is also its persisted shape.
    var coreValue: [String: Any] {
        let key: [String: Any] = switch self.key {
        case .character(let character): ["character": String(character)]
        case .special(let special): ["special": special.rawValue]
        }
        return ["key": key, "modifiers": modifiers.rawValue]
    }

    init?(coreValue: Any?) {
        guard let value = coreValue as? [String: Any], let key = value["key"] as? [String: Any],
            let modifiers = value["modifiers"] as? Int
        else { return nil }
        if let text = key["character"] as? String, text.count == 1, let character = text.first {
            self.init(key: .character(character), modifiers: BrowserShortcutModifiers(rawValue: modifiers))
        } else if let raw = key["special"] as? String, let special = BrowserShortcutSpecialKey(rawValue: raw) {
            self.init(key: .special(special), modifiers: BrowserShortcutModifiers(rawValue: modifiers))
        } else {
            return nil
        }
    }
}

/// Shortcut rules owned by the portable core: the default catalog, how
/// overrides resolve, conflicts, and what the numbered commands select.
/// Section grouping and search for the settings list stay native.
extension BrowserCorePolicy {
    /// Crest's default chords for this platform. Empty only when the core
    /// cannot answer, which leaves every command without a default.
    static let defaultShortcuts: [BrowserShortcutCommand: BrowserShortcut] =
        shortcutBindings(overrides: [:], commands: BrowserShortcutCommand.allCases)?.defaults ?? [:]

    /// Live chords for `commands`. Nil when the core cannot answer; the caller
    /// then binds nothing rather than guessing.
    static func shortcutBindings(overrides: [String: BrowserShortcutOverride],
        commands: [BrowserShortcutCommand]) -> BrowserShortcutBindings? {
        guard let response = evaluate([
            "version": 1, "operation": "shortcuts.bindings", "platform": devicePlatform,
            "commands": commands.map(\.rawValue), "overrides": coreOverrides(overrides),
        ]), let values = response["bindings"] as? [[String: Any]] else { return nil }
        var bindings = BrowserShortcutBindings()
        for value in values {
            guard let raw = value["command"] as? String, let command = BrowserShortcutCommand(rawValue: raw) else { return nil }
            if let shortcut = BrowserShortcut(coreValue: value["shortcut"]) { bindings.shortcuts[command] = shortcut }
            if let shortcut = BrowserShortcut(coreValue: value["default"]) { bindings.defaults[command] = shortcut }
        }
        return bindings
    }

    /// Binds `shortcut` to `command`, or clears it when `shortcut` is nil, and
    /// returns the revised overrides when the binding applies. A core that
    /// cannot answer reports a conflict, so nothing is ever bound twice.
    static func assignShortcut(_ shortcut: BrowserShortcut?, to command: BrowserShortcutCommand,
        replacingConflicts: Bool, overrides: [String: BrowserShortcutOverride], commands: [BrowserShortcutCommand])
        -> (result: BrowserShortcutAssignmentResult, overrides: [String: BrowserShortcutOverride]?) {
        let unavailable: (BrowserShortcutAssignmentResult, [String: BrowserShortcutOverride]?) = (.conflict(commands: []), nil)
        guard let response = evaluate([
            "version": 1, "operation": "shortcuts.assign", "platform": devicePlatform,
            "commands": commands.map(\.rawValue), "overrides": coreOverrides(overrides),
            "command": command.rawValue, "shortcut": shortcut?.coreValue as Any? ?? NSNull(),
            "replacingConflicts": replacingConflicts,
        ]), let result = response["result"] as? String else { return unavailable }
        switch result {
        case "assigned":
            guard let revised = response["overrides"] as? [String: Any] else { return unavailable }
            var decoded: [String: BrowserShortcutOverride] = [:]
            for (key, value) in revised {
                if value is NSNull {
                    decoded[key] = .unassigned
                } else if let custom = BrowserShortcut(coreValue: value) {
                    decoded[key] = .custom(custom)
                } else {
                    return unavailable
                }
            }
            return (.assigned, decoded)
        case "invalid":
            return (.invalid, nil)
        default:
            let conflicts = (response["conflicts"] as? [String] ?? []).compactMap(BrowserShortcutCommand.init(rawValue:))
            return (.conflict(commands: conflicts), nil)
        }
    }

    /// Where each numbered selection command leads for these counts. A command
    /// with nowhere to go is absent, and so is every command when the core
    /// cannot answer.
    static func numberedSelections(tabCount: Int, spaceCount: Int) -> [BrowserShortcutCommand: BrowserNumberedSelection] {
        guard let values = evaluate([
            "version": 1, "operation": "shortcuts.numbered_selection", "tabCount": tabCount, "spaceCount": spaceCount,
        ])?["selections"] as? [[String: Any]] else { return [:] }
        var selections: [BrowserShortcutCommand: BrowserNumberedSelection] = [:]
        for value in values {
            guard let raw = value["command"] as? String, let command = BrowserShortcutCommand(rawValue: raw),
                let index = value["index"] as? Int
            else { continue }
            selections[command] = value["target"] as? String == "space" ? .space(index) : .tab(index)
        }
        return selections
    }

    private static func coreOverrides(_ overrides: [String: BrowserShortcutOverride]) -> [String: Any] {
        overrides.mapValues { value -> Any in
            switch value {
            case .custom(let shortcut): shortcut.coreValue
            case .unassigned: NSNull()
            }
        }
    }
}
