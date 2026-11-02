import AppKit

/// The menu bar's top menu. AppKit offers it every key equivalent no view
/// took, and a page's engine hands it each key the page let go. Its items
/// match most of Crest's chords themselves; the shell runs a command whose
/// chord no item matches, such as zoom's ⌘= for the item's ⌘+.
final class BrowserMacMainMenu: NSMenu {
    // MARK: - Variables

    weak var shell: BrowserMacShell?
    /// The items that answer a second chord their menu doesn't show, since an
    /// item shows one.
    var aliases: [(chord: BrowserShortcut, item: NSMenuItem)] = []

    // MARK: - Actions - Key equivalents

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        if performAlias(for: event) { return true }
        guard let shell else { return false }
        // AppKit and the engines ask the menu bar about keys on the main
        // thread only.
        nonisolated(unsafe) let event = event
        return MainActor.assumeIsolated { shell.handleShortcut(event, pageSeesFirst: false) }
    }

    /// Runs the item `event`'s chord is an alias of, as its own chord would,
    /// when the item is enabled.
    private func performAlias(for event: NSEvent) -> Bool {
        nonisolated(unsafe) let event = event
        nonisolated(unsafe) let aliases = aliases
        return MainActor.assumeIsolated {
            guard let chord = BrowserShortcut(event: event),
                let item = aliases.first(where: { $0.chord == chord })?.item,
                let action = item.action,
                (item.target as? NSMenuItemValidation)?.validateMenuItem(item) == true
            else { return false }
            return NSApp.sendAction(action, to: item.target, from: item)
        }
    }
}
