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
