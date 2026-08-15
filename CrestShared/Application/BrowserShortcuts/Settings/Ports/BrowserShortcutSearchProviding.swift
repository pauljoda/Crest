protocol BrowserShortcutSearchProviding {
    func matches(
        _ command: BrowserShortcutCommand,
        currentShortcut: BrowserShortcut?,
        query: String
    ) -> Bool
    func matches(
        _ command: BrowserShortcutExtensionCommand,
        query: String
    ) -> Bool
}
