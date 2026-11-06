import Foundation

/// The platform's side of the core's shortcut bindings.
///
/// The core owns the catalog, the person's choices, conflicts, which commands
/// this device offers, and what the numbered commands reach; the device store
/// keeps the choices. This store reads each offered command's live chord from
/// the read model and sends the person's changes as intents.
@MainActor
final class BrowserShortcutStore {
    // MARK: - Static Variables

    private static let log = DiagnosticLog.shortcuts

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
            Self.log.error(
                "The core could not adopt the saved shortcuts: \(DiagnosticLog.describe(error))")
        }
    }

    /// A store over a memory-only core of its own, as previews and tests
    /// use, which keeps nothing.
    convenience init() {
        self.init(core: CrestCore())
    }

    // MARK: - Actions - Adoption

    /// Names, once, the shortcuts an earlier release saved with the symbol
    /// Shift types on a digit key by that digit, reading `digits` from the
    /// keyboard layout in use.
    func adoptShiftedDigits(_ digits: [ShiftedDigit]) {
        do {
            try core.send(AdoptShiftedDigitShortcuts(digits: digits))
        } catch {
            Self.log.error(
                "The core could not rename the saved shifted digits: \(DiagnosticLog.describe(error))")
        }
    }

    // MARK: - Actions - Bindings

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        core.state.shortcuts[command]?.keys.flatMap(BrowserShortcut.init(boundKeys:))
    }

    func isCustomized(_ command: ShortcutCommand) -> Bool {
        core.state.shortcuts[command]?.isCustomized == true
    }

    /// Who answers `command`'s keys while a focused page uses them too.
    func preference(for command: ShortcutCommand) -> ShortcutPreference {
        core.state.shortcuts[command]?.preference ?? command.defaultPreference
    }

    /// Whether a person may choose who answers `command`'s keys: a command
    /// reserved from pages, or one bound to text editing keys, cannot.
    func choosesPreference(_ command: ShortcutCommand) -> Bool {
        core.state.shortcuts[command]?.choosesPreference == true
    }

    /// Whether `command` is bound to keys a focused text field edits with, so
    /// it takes them only when the field has nothing to do with them.
    func yieldsToTextEditing(_ command: ShortcutCommand) -> Bool {
        core.state.shortcuts[command]?.yieldsToTextEditing == true
    }

    func commands(assignedTo shortcut: BrowserShortcut) -> [ShortcutCommand] {
        let keys = shortcut.keys
        return core.state.shortcutBindings.filter { $0.keys == keys }.map(\.command)
    }

    // MARK: - Actions - Changes

    /// Binds `shortcut` to `command` unless another command holds it.
    func assign(_ shortcut: BrowserShortcut, to command: ShortcutCommand) -> any BrowserShortcutAssignmentResult {
        answer(AssignShortcut(command: command, keys: shortcut.keys))
    }

    /// Binds `shortcut` to `command`, taking it from every command that holds it.
    func reassign(_ shortcut: BrowserShortcut, to command: ShortcutCommand) -> any BrowserShortcutAssignmentResult {
        answer(ReassignShortcut(command: command, keys: shortcut.keys))
    }

    /// Makes `preference` answer `command`'s keys while a focused page uses
    /// them too.
    func choose(_ preference: ShortcutPreference, for command: ShortcutCommand) {
        _ = answer(ChooseShortcutPreference(command: command, preference: preference))
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

    private func answer(_ intent: some ShortcutIntent) -> any BrowserShortcutAssignmentResult {
        do {
            try core.send(intent)
            return BrowserShortcutAssigned()
        } catch .shortcutInUse(let refusal) {
            return BrowserShortcutInUse(commands: refusal.commands)
        } catch .invalidShortcut {
            return BrowserShortcutInvalid()
        } catch {
            Self.log.error(
                "The core refused \(String(describing: type(of: intent))): \(DiagnosticLog.describe(error))"
            )
            return BrowserShortcutInvalid()
        }
    }
}
