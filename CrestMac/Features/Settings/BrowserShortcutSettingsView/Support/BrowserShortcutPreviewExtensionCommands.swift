@MainActor
final class BrowserShortcutPreviewExtensionCommands:
    BrowserShortcutExtensionCommandManaging
{
    func commands(
        in _: SpaceID
    ) -> [BrowserShortcutExtensionCommand] {
        [
            BrowserShortcutExtensionCommand(
                extensionID: "preview.reader-tools",
                extensionDisplayName: "Reader Tools",
                commandID: "capture",
                title: "Capture Article",
                shortcut: BrowserShortcut(
                    key: .character("c"),
                    modifiers: [.command, .option]
                ),
                isCustomized: true
            )
        ]
    }

    func supports(_ shortcut: BrowserShortcut) -> Bool {
        shortcut.isValid
    }

    func setShortcut(
        _: BrowserShortcut?,
        commandID _: String,
        extensionID _: String,
        in _: SpaceID
    ) {}

    func resetShortcut(
        commandID _: String,
        extensionID _: String,
        in _: SpaceID
    ) {}
}
