struct BrowserShortcutExtensionCommandGroupID:
    Equatable,
    Hashable,
    Sendable
{
    let spaceID: SpaceID
    let extensionID: String
}
