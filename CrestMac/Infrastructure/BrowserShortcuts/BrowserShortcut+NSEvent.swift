import AppKit

extension BrowserShortcut {
    init?(event: some BrowserShortcutKeyPress) {
        let modifiers = ShortcutModifiers(event.modifierFlags)
        guard let key = BrowserShortcutKey(event: event) else { return nil }
        self.init(key: key, modifiers: modifiers)
    }

    /// The chord a menu item's key equivalent names, or nil for an item
    /// without one.
    init?(keyEquivalentOf item: NSMenuItem) {
        guard item.keyEquivalent.count == 1, let character = item.keyEquivalent.lowercased().first else { return nil }
        self.init(key: .character(character), modifiers: ShortcutModifiers(item.keyEquivalentModifierMask))
    }
}
