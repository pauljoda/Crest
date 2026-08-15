enum BrowserShortcutConflictPolicy {
    static func conflicts(
        assigning shortcut: BrowserShortcut,
        to command: BrowserShortcutCommand,
        currentAssignments: [BrowserShortcutCommand: BrowserShortcut]
    ) -> [BrowserShortcutCommand] {
        BrowserShortcutCommand.userFacingCases.filter {
            $0 != command && currentAssignments[$0] == shortcut
        }
    }
}
