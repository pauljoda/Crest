/// Commands and shortcut metadata supplied by the presenting platform shell.
@MainActor
struct BrowserCommandPaletteCommandRegistry {
    let commands: [ShortcutCommand]
    private let shortcutProvider: (ShortcutCommand) -> BrowserShortcut?
    private let performer: (ShortcutCommand) -> Void

    init(
        commands: [ShortcutCommand],
        shortcut: @escaping (ShortcutCommand) -> BrowserShortcut? = { _ in nil },
        perform: @escaping (ShortcutCommand) -> Void
    ) {
        self.commands = commands
        shortcutProvider = shortcut
        performer = perform
    }

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        shortcutProvider(command)
    }

    func perform(_ command: ShortcutCommand) {
        performer(command)
    }
}
