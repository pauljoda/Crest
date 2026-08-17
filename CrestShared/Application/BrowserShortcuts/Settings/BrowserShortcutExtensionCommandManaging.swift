@MainActor
protocol BrowserShortcutExtensionCommandManaging: AnyObject {
    func commands(in spaceID: SpaceID) -> [BrowserShortcutExtensionCommand]
    func supports(_ shortcut: BrowserShortcut) -> Bool
    func setShortcut(
        _ shortcut: BrowserShortcut?,
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID
    )
    func resetShortcut(
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID
    )
}
