struct BrowserShortcutCommandGroup: Equatable, Identifiable, Sendable {
    let section: BrowserShortcutSection
    let commands: [BrowserShortcutCommand]

    var id: BrowserShortcutSection { section }
}

struct BrowserShortcutPendingConflict: Equatable, Sendable {
    let command: BrowserShortcutCommand
    let shortcut: BrowserShortcut
    let conflictingCommands: [BrowserShortcutCommand]
}

enum BrowserShortcutValidationIssue: Equatable, Sendable {
    case invalidShortcut
    case reservedByCrest(
        shortcut: BrowserShortcut,
        commands: [BrowserShortcutCommand]
    )
}
