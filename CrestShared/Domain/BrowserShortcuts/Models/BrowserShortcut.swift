struct BrowserShortcut: Codable, Equatable, Hashable, Sendable {
    let key: BrowserShortcutKey
    let modifiers: BrowserShortcutModifiers

    var isValid: Bool {
        !modifiers.intersection(.supported).isEmpty
    }
}
