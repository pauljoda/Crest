import AppKit

/// A key press a shortcut is read from. `NSEvent` reads it through the
/// current input source, and tests through a chosen layout's tables.
protocol BrowserShortcutKeyPress {
    var keyCode: UInt16 { get }
    var modifierFlags: NSEvent.ModifierFlags { get }
    var charactersIgnoringModifiers: String? { get }
    func characters(byApplyingModifiers modifiers: NSEvent.ModifierFlags) -> String?
}

extension BrowserShortcutKeyPress {
    /// The characters a shortcut names the key by. Layouts such as Dvorak –
    /// QWERTY ⌘ and Russian type from another layer while ⌘ is held, where
    /// the menu bar matches key equivalents, so a chord with ⌘ on such a key
    /// reads that layer with Shift. Every other press reads as typed, since
    /// the ⌘ layer of other layouts drops Shift and saved ⌘⇧ shortcuts would
    /// change meaning.
    var shortcutCharacters: String? {
        // A dead key types nothing as typed but its accent once modifiers
        // apply, so comparing with `charactersIgnoringModifiers` would read
        // every dead key as a ⌘ layer.
        guard modifierFlags.contains(.command),
            characters(byApplyingModifiers: .command) != characters(byApplyingModifiers: [])
        else { return charactersIgnoringModifiers }
        return characters(byApplyingModifiers: modifierFlags.intersection([.command, .shift]))
    }
}

extension NSEvent: BrowserShortcutKeyPress {}
