extension BrowserExtensionControllerPool:
    BrowserShortcutExtensionCommandManaging
{
    func commands(
        in spaceID: SpaceID
    ) -> [BrowserShortcutExtensionCommand] {
        extensionCommands(in: spaceID).map { command in
            BrowserShortcutExtensionCommand(
                extensionID: command.extensionID,
                extensionDisplayName: command.extensionDisplayName,
                commandID: command.commandID,
                title: command.title,
                shortcut: command.shortcut,
                isCustomized: command.isCustomized
            )
        }
    }

    func supports(_ shortcut: BrowserShortcut) -> Bool {
        shortcut.isValid
            && BrowserExtensionShortcutPolicy.activationKey(
                for: shortcut.key
            ) != nil
    }
}
