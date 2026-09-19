protocol BrowserShortcutSearchProviding {
    func matches(
        _ command: BrowserShortcutCommand,
        currentShortcut: BrowserShortcut?,
        query: String
    ) -> Bool
}
