enum BrowserShortcutPersistenceRecord: Codable {
    case custom(BrowserShortcut)
    case unassigned

    init(_ shortcutOverride: BrowserShortcutOverride) {
        switch shortcutOverride {
        case .custom(let shortcut): self = .custom(shortcut)
        case .unassigned: self = .unassigned
        }
    }

    var shortcutOverride: BrowserShortcutOverride {
        switch self {
        case .custom(let shortcut): .custom(shortcut)
        case .unassigned: .unassigned
        }
    }
}
