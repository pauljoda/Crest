struct BrowserShortcutExtensionCommand: Equatable, Identifiable, Sendable {
    let extensionID: String
    let extensionDisplayName: String
    let commandID: String
    let title: String
    let shortcut: BrowserShortcut?
    let isCustomized: Bool

    var id: BrowserShortcutExtensionCommandID {
        BrowserShortcutExtensionCommandID(
            extensionID: extensionID,
            commandID: commandID
        )
    }
}
