struct BrowserShortcutCommandGroup: Equatable, Identifiable, Sendable {
    let section: BrowserShortcutSection
    let commands: [BrowserShortcutCommand]

    var id: BrowserShortcutSection { section }
}

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

struct BrowserShortcutExtensionCommandGroup:
    Equatable,
    Identifiable,
    Sendable
{
    let extensionID: String
    let extensionName: String
    let spaceID: SpaceID
    let spaceName: String
    let commands: [BrowserShortcutExtensionCommand]

    var id: BrowserShortcutExtensionCommandGroupID {
        BrowserShortcutExtensionCommandGroupID(
            spaceID: spaceID,
            extensionID: extensionID
        )
    }
}

struct BrowserShortcutExtensionCommandGroupID:
    Equatable,
    Hashable,
    Sendable
{
    let spaceID: SpaceID
    let extensionID: String
}

struct BrowserShortcutExtensionCommandID: Equatable, Hashable, Sendable {
    let extensionID: String
    let commandID: String

    var rawValue: String {
        "\(extensionID).\(commandID)"
    }
}

struct BrowserShortcutPendingConflict: Equatable, Sendable {
    let command: BrowserShortcutCommand
    let shortcut: BrowserShortcut
    let conflictingCommands: [BrowserShortcutCommand]
}

struct BrowserShortcutScrollRequest: Equatable, Sendable {
    let revision: Int
    let targetID: BrowserShortcutExtensionCommandID
}

enum BrowserShortcutValidationIssue: Equatable, Sendable {
    case invalidShortcut
    case reservedByCrest(
        shortcut: BrowserShortcut,
        commands: [BrowserShortcutCommand]
    )
}
