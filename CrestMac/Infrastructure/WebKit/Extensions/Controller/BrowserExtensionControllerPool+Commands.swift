import AppKit

extension BrowserExtensionControllerPool {
    func extensionCommands(
        in spaceID: SpaceID
    ) -> [BrowserExtensionCommandSummary] {
        _ = actionRevision
        return commandController.extensionCommands(
            summaries: extensions(in: spaceID),
            in: spaceID,
            context: {
                self.loadedContext(extensionID: $0, in: spaceID)
            }
        )
    }

    func setShortcut(
        _ shortcut: BrowserShortcut?,
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        let mutationCount = commandController.setShortcut(
            shortcut,
            commandID: commandID,
            extensionID: extensionID,
            in: spaceID,
            summaries: extensions(in: spaceID),
            context: {
                self.loadedContext(extensionID: $0, in: spaceID)
            }
        )
        recordActionMutations(mutationCount)
    }

    func resetShortcut(
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        let didReset = commandController.resetShortcut(
            commandID: commandID,
            extensionID: extensionID,
            in: spaceID,
            context: {
                self.loadedContext(extensionID: $0, in: spaceID)
            }
        )
        recordActionMutations(didReset ? 1 : 0)
    }

    func performCommand(
        for event: NSEvent,
        in spaceID: SpaceID
    ) -> Bool {
        commandController.performCommand(
            for: event,
            summaries: extensions(in: spaceID),
            context: {
                self.loadedContext(extensionID: $0, in: spaceID)
            },
            activeTab: {
                self.tabWindowCoordinator.activeTab(
                    in: spaceID,
                    context: $0
                )
            }
        )
    }

    func perform(
        _ command: BrowserExtensionToolbarCommand,
        in spaceID: SpaceID
    ) {
        commandController.perform(
            command,
            activeTab: {
                self.tabWindowCoordinator.activeTab(
                    in: spaceID,
                    context: $0
                )
            }
        )
    }
}
