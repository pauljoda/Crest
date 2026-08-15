import AppKit

extension BrowserShortcut {
    init?(event: NSEvent) {
        let modifiers = BrowserShortcutModifiers(event.modifierFlags)
        guard let key = BrowserShortcutKey(event: event) else { return nil }
        self.init(key: key, modifiers: modifiers)
    }
}
