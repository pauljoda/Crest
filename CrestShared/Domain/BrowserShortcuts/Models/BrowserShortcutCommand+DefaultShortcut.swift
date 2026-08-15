extension BrowserShortcutCommand {
    var defaultShortcut: BrowserShortcut? {
        BrowserShortcutDefaultPolicy.shortcut(for: self)
    }
}
