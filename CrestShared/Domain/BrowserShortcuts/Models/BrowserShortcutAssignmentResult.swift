enum BrowserShortcutAssignmentResult: Equatable, Sendable {
    case assigned
    case conflict(commands: [BrowserShortcutCommand])
    case invalid
}
