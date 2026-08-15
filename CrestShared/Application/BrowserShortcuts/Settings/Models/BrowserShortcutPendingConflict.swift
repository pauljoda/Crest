struct BrowserShortcutPendingConflict: Equatable, Sendable {
    let command: BrowserShortcutCommand
    let shortcut: BrowserShortcut
    let conflictingCommands: [BrowserShortcutCommand]
}
