extension BrowserCommandPaletteResults {
    static let restingCommands: [BrowserShortcutCommand] = [
        .newWindow,
        .reopenClosedTab,
        .showHistory,
        .showDownloads,
        .toggleSidebar,
    ]

    static let excludedCommands: Set<BrowserShortcutCommand> = [
        .newTab,
        .openLocation,
    ]
}
