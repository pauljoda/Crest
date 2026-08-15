enum BrowserPeekKeyboardPolicy {
    static func action(
        forKeyCode keyCode: UInt16,
        modifierFlags: BrowserKeyboardModifierFlags
    ) -> BrowserPeekKeyboardAction? {
        let disallowedModifiers: BrowserKeyboardModifierFlags = [
            .command,
            .control,
            .option,
        ]
        guard modifierFlags.intersection(disallowedModifiers).isEmpty else {
            return nil
        }
        switch keyCode {
        case 53:
            return .dismiss
        default:
            return nil
        }
    }
}
