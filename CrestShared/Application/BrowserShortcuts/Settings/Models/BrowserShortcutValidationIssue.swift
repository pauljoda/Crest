enum BrowserShortcutValidationIssue: Equatable, Sendable {
    case invalidShortcut
    case reservedByCrest(
        shortcut: BrowserShortcut,
        commands: [BrowserShortcutCommand]
    )
}
