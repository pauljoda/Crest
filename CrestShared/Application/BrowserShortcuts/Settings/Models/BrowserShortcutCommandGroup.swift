struct BrowserShortcutCommandGroup: Equatable, Identifiable, Sendable {
    let section: BrowserShortcutSection
    let commands: [BrowserShortcutCommand]

    var id: BrowserShortcutSection { section }
}
