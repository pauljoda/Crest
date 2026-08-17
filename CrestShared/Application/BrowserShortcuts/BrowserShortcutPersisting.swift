protocol BrowserShortcutPersisting {
    func load() -> [String: BrowserShortcutOverride]?
    func save(_ overrides: [String: BrowserShortcutOverride])
    func remove()
}
