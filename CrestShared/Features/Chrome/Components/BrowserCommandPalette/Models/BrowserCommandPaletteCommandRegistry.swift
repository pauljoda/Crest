/// Commands and shortcut metadata supplied by the presenting platform shell.
@MainActor
struct BrowserCommandPaletteCommandRegistry {
    let commands: [BrowserShortcutCommand]
    private let shortcutProvider: (BrowserShortcutCommand) -> BrowserShortcut?
    private let performer: (BrowserShortcutCommand) -> Void

    init(
        commands: [BrowserShortcutCommand],
        shortcut: @escaping (BrowserShortcutCommand) -> BrowserShortcut? = { _ in nil },
        perform: @escaping (BrowserShortcutCommand) -> Void
    ) {
        self.commands = commands
        shortcutProvider = shortcut
        performer = perform
    }

    func shortcut(for command: BrowserShortcutCommand) -> BrowserShortcut? {
        shortcutProvider(command)
    }

    func perform(_ command: BrowserShortcutCommand) {
        performer(command)
    }
}
