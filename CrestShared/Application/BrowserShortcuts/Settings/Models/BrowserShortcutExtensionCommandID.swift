struct BrowserShortcutExtensionCommandID: Equatable, Hashable, Sendable {
    let extensionID: String
    let commandID: String

    var rawValue: String {
        "\(extensionID).\(commandID)"
    }
}
