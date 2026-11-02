import AppKit

/// The menu bar's top menu. AppKit offers it every key equivalent no view
/// took, and a page's engine hands it each key the page let go. Its items
/// match most of Crest's chords themselves; the shell runs a command whose
/// chord no item matches, such as zoom's ⌘= for the item's ⌘+.
final class BrowserMacMainMenu: NSMenu {
    // MARK: - Variables

    weak var shell: BrowserMacShell?
    /// Items that answer a second chord their menu doesn't show, since an item
    /// shows one. AppKit matches these chords as it matches the menu's own, so
    /// a layout that moves letters while ⌘ is held still finds them.
    let aliases = NSMenu()

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

    /// Runs the alias item `event`'s chord matches, if it is enabled.
    private func performAlias(for event: NSEvent) -> Bool {
        nonisolated(unsafe) let event = event
        nonisolated(unsafe) let aliases = aliases
        return MainActor.assumeIsolated { aliases.performKeyEquivalent(with: event) }
    }
}
