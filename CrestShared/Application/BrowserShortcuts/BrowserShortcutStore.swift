import Foundation
import os

/// The platform's side of the core's shortcut bindings.
///
/// The core owns the catalog, the person's choices, conflicts, which commands
/// this device offers, and what the numbered commands reach; the device store
/// keeps the choices. This store reads each offered command's live chord from
/// the read model and sends the person's changes as intents.
@MainActor
final class BrowserShortcutStore {
    // MARK: - Static Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Shortcuts")

    // MARK: - Variables

    private let core: CrestCore

    /// Whether the person changed any shortcut, including one this device does
    /// not offer.
    var hasCustomizations: Bool {
        core.state.shortcutsAreCustomized
    }

    /// The commands this device offers, in the order the settings list them.
    var offeredCommands: [ShortcutCommand] {
        core.state.shortcutBindings.map(\.command)
    }

    // MARK: - Initializers

    /// A store over `core`. It carries the choices an installed release kept
    /// under `crest.keyboard-shortcuts.v1`, `legacyOverrides`, into the core's
    /// device store once, and reads every offered command's chord.
    init(core: CrestCore, legacyOverrides: Data? = nil) {
        self.core = core
        do {
            try core.send(AdoptShortcuts(overrides: legacyOverrides))
        } catch {
            Self.logger.error(
                "The core could not adopt the saved shortcuts: \(String(describing: error), privacy: .public)")
        }
    }

    /// A store over a memory-only core of its own, as previews and tests
    /// use, which keeps nothing.
    convenience init() {
        self.init(core: CrestCore())
    }

    // MARK: - Actions - Bindings

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        core.state.shortcuts[command]?.keys.flatMap(BrowserShortcut.init(boundKeys:))
    }

    func isCustomized(_ command: ShortcutCommand) -> Bool {
        core.state.shortcuts[command]?.isCustomized == true
    }

    func commands(assignedTo shortcut: BrowserShortcut) -> [ShortcutCommand] {
        let keys = shortcut.keys
        return core.state.shortcutBindings.filter { $0.keys == keys }.map(\.command)
    }

    // MARK: - Actions - Changes

    /// Binds `shortcut` to `command` unless another command holds it.
    func assign(_ shortcut: BrowserShortcut, to command: ShortcutCommand) -> BrowserShortcutAssignmentResult {
        answer(AssignShortcut(command: command, keys: shortcut.keys))
    }

    /// Binds `shortcut` to `command`, taking it from every command that holds it.
    func reassign(_ shortcut: BrowserShortcut, to command: ShortcutCommand) -> BrowserShortcutAssignmentResult {
        answer(ReassignShortcut(command: command, keys: shortcut.keys))
    }

    func clearShortcut(for command: ShortcutCommand) {
        _ = answer(UnassignShortcut(command: command))
    }

    func reset(_ command: ShortcutCommand) {
        _ = answer(ResetShortcut(command: command))
    }

    func resetAll() {
        _ = answer(ResetShortcuts())
    }

    private func answer(_ intent: some ShortcutIntent) -> BrowserShortcutAssignmentResult {
        do {
            try core.send(intent)
            return .assigned
        } catch .shortcutInUse(let refusal) {
            return .conflict(commands: refusal.commands)
        } catch .invalidShortcut {
            return .invalid
        } catch {
            Self.logger.error(
                "The core refused \(String(describing: type(of: intent)), privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return .invalid
        }
    }
}
