import AppKit
import WebKit

extension BrowserExtensionCommandController {
    func captureDefaults(
        for context: WKWebExtensionContext,
        extensionID: String,
        spaceID: SpaceID
    ) {
        defaultsBySpace[spaceID, default: [:]][extensionID] = Dictionary(
            uniqueKeysWithValues: context.commands.map {
                (
                    $0.id,
                    shortcut(for: $0).map(
                        BrowserExtensionCommandShortcutOverride.custom
                    ) ?? .unassigned
                )
            }
        )
    }

    func applyStoredShortcuts(
        to context: WKWebExtensionContext,
        extensionID: String,
        spaceID: SpaceID
    ) {
        let overrides =
            persistence.installation(
                extensionID: extensionID,
                in: spaceID
            )?.commandShortcutOverrides ?? [:]
        for command in context.commands {
            switch overrides[command.id] {
            case .custom(let shortcut):
                apply(shortcut, to: command)
            case .unassigned:
                apply(nil, to: command)
            case nil:
                break
            }
        }
    }

    func releaseContext(extensionID: String, in spaceID: SpaceID) {
        defaultsBySpace[spaceID]?.removeValue(forKey: extensionID)
        if defaultsBySpace[spaceID]?.isEmpty == true {
            defaultsBySpace.removeValue(forKey: spaceID)
        }
    }

    func extensionCommands(
        summaries: [BrowserExtensionSummary],
        in spaceID: SpaceID,
        context: (String) -> WKWebExtensionContext?
    ) -> [BrowserExtensionCommandSummary] {
        summaries.flatMap { summary -> [BrowserExtensionCommandSummary] in
            guard summary.isEnabled,
                let context = context(summary.id)
            else {
                return []
            }
            let overrides =
                persistence.installation(
                    extensionID: summary.id,
                    in: spaceID
                )?.commandShortcutOverrides ?? [:]
            return context.commands.map { command in
                BrowserExtensionCommandSummary(
                    extensionID: summary.id,
                    extensionDisplayName: summary.displayName,
                    commandID: command.id,
                    title: command.title,
                    shortcut: shortcut(for: command),
                    isCustomized: overrides[command.id] != nil
                )
            }
        }
        .sorted {
            if $0.extensionDisplayName != $1.extensionDisplayName {
                return $0.extensionDisplayName.localizedStandardCompare(
                    $1.extensionDisplayName
                ) == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title)
                == .orderedAscending
        }
    }

    func setShortcut(
        _ shortcut: BrowserShortcut?,
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID,
        summaries: [BrowserExtensionSummary],
        context: (String) -> WKWebExtensionContext?
    ) -> Int {
        if let shortcut {
            guard shortcut.isValid,
                BrowserExtensionShortcutPolicy.activationKey(
                    for: shortcut.key
                ) != nil
            else {
                return 0
            }
        }

        var mutationCount = 0
        if let shortcut {
            let conflicts = extensionCommands(
                summaries: summaries,
                in: spaceID,
                context: context
            )
            for conflict in conflicts
            where
                conflict.shortcut == shortcut
                && (conflict.extensionID != extensionID
                    || conflict.commandID != commandID)
            {
                if applyShortcut(
                    nil,
                    commandID: conflict.commandID,
                    extensionID: conflict.extensionID,
                    in: spaceID,
                    persist: true,
                    context: context
                ) {
                    mutationCount += 1
                }
            }
        }
        if applyShortcut(
            shortcut,
            commandID: commandID,
            extensionID: extensionID,
            in: spaceID,
            persist: true,
            context: context
        ) {
            mutationCount += 1
        }
        return mutationCount
    }

    func resetShortcut(
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID,
        context: (String) -> WKWebExtensionContext?
    ) -> Bool {
        guard
            let command = command(
                commandID: commandID,
                extensionID: extensionID,
                context: context
            )
        else {
            return false
        }
        persistence.resetCommandShortcutOverride(
            commandID: commandID,
            extensionID: extensionID,
            in: spaceID
        )
        let defaultShortcut: BrowserShortcut?
        switch defaultsBySpace[spaceID]?[extensionID]?[commandID] {
        case .custom(let shortcut):
            defaultShortcut = shortcut
        case .unassigned, nil:
            defaultShortcut = nil
        }
        apply(defaultShortcut, to: command)
        return true
    }

    func performCommand(
        for event: NSEvent,
        summaries: [BrowserExtensionSummary],
        context: (String) -> WKWebExtensionContext?,
        activeTab: (WKWebExtensionContext) -> (any WKWebExtensionTab)?
    ) -> Bool {
        guard event.type == .keyDown, !event.isARepeat else { return false }
        let pressed = BrowserShortcut(event: event)
        for summary in summaries where summary.isEnabled {
            guard let context = context(summary.id) else { continue }
            // Only the extension whose own shortcut matches earns the gesture;
            // an unrelated keystroke must not hand out activeTab.
            if let pressed,
                context.commands.contains(where: { shortcut(for: $0) == pressed })
            {
                grantActiveTab(in: context, activeTab: activeTab)
            }
            if context.performCommand(for: event) {
                return true
            }
        }
        return false
    }

    func perform(
        _ command: BrowserExtensionToolbarCommand,
        activeTab: (WKWebExtensionContext) -> (any WKWebExtensionTab)?
    ) {
        guard let context = command.command.webExtensionContext else { return }
        grantActiveTab(in: context, activeTab: activeTab)
        context.performCommand(command.command)
    }

    /// Chrome and Safari treat invoking a command as the user gesture that
    /// earns `activeTab`, so Crest reports the gesture on the Space's active tab
    /// before the command runs.
    private func grantActiveTab(
        in context: WKWebExtensionContext,
        activeTab: (WKWebExtensionContext) -> (any WKWebExtensionTab)?
    ) {
        guard let tab = activeTab(context) else { return }
        context.userGesturePerformed(in: tab)
    }

    private func applyShortcut(
        _ shortcut: BrowserShortcut?,
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID,
        persist: Bool,
        context: (String) -> WKWebExtensionContext?
    ) -> Bool {
        guard
            let command = command(
                commandID: commandID,
                extensionID: extensionID,
                context: context
            )
        else {
            return false
        }
        if persist {
            persistence.setCommandShortcutOverride(
                shortcut.map(
                    BrowserExtensionCommandShortcutOverride.custom
                ) ?? .unassigned,
                commandID: commandID,
                extensionID: extensionID,
                in: spaceID
            )
        }
        apply(shortcut, to: command)
        return true
    }

    private func command(
        commandID: String,
        extensionID: String,
        context: (String) -> WKWebExtensionContext?
    ) -> WKWebExtension.Command? {
        context(extensionID)?.commands.first { $0.id == commandID }
    }

    private func shortcut(
        for command: WKWebExtension.Command
    ) -> BrowserShortcut? {
        BrowserExtensionShortcutPolicy.shortcut(
            activationKey: command.activationKey,
            modifiers: BrowserShortcutModifiers(command.modifierFlags)
        )
    }

    private func apply(
        _ shortcut: BrowserShortcut?,
        to command: WKWebExtension.Command
    ) {
        command.activationKey = shortcut.flatMap {
            BrowserExtensionShortcutPolicy.activationKey(for: $0.key)
        }
        command.modifierFlags = shortcut?.modifiers.appKitModifierFlags ?? []
    }
}
