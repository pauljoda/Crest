import Foundation

extension CoreState {
    /// The core publishes every offered command's binding at once.
    func apply(_ change: ShortcutsChanged) {
        shortcutBindings = change.bindings
        shortcuts = Dictionary(change.bindings.map { ($0.command, $0) }, uniquingKeysWith: { first, _ in first })
        shortcutsAreCustomized = change.isCustomized
    }
}
