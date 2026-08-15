struct BrowserShortcutScrollRequest: Equatable, Sendable {
    let revision: Int
    let targetID: BrowserShortcutExtensionCommandID
}
