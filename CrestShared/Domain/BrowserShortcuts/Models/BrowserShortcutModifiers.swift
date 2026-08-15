struct BrowserShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let command = BrowserShortcutModifiers(rawValue: 1 << 0)
    static let option = BrowserShortcutModifiers(rawValue: 1 << 1)
    static let control = BrowserShortcutModifiers(rawValue: 1 << 2)
    static let shift = BrowserShortcutModifiers(rawValue: 1 << 3)

    static let supported: BrowserShortcutModifiers = [
        .command,
        .option,
        .control,
        .shift,
    ]
}
