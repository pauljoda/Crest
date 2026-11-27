import Foundation

/// Commands, settings pages and the window's own actions, supplied by the
/// presenting platform shell, which palette rows other than addresses and
/// tabs perform.
@MainActor
struct BrowserCommandPaletteCommandRegistry {
    let commands: [ShortcutCommand]
    /// The settings pages the palette may open, by their settings name.
    let settingsPages: [PaletteSettingsPage]
    private let shortcutProvider: (ShortcutCommand) -> BrowserShortcut?
    private let performer: (ShortcutCommand) -> Void
    private let settingsOpener: (BrowserSettingsDestination) -> Void
    private let spaceSwitcher: (UUID) -> Void
    private let archiveReopener: (UUID) -> Void
    private let copier: (String) -> Void

    init(
        commands: [ShortcutCommand],
        settingsPages: [PaletteSettingsPage] = [],
        shortcut: @escaping (ShortcutCommand) -> BrowserShortcut? = { _ in nil },
        perform: @escaping (ShortcutCommand) -> Void,
        openSettings: @escaping (BrowserSettingsDestination) -> Void = { _ in },
        switchSpace: @escaping (UUID) -> Void = { _ in },
        reopenArchivedTab: @escaping (UUID) -> Void = { _ in },
        copy: @escaping (String) -> Void = { _ in }
    ) {
        self.commands = commands
        self.settingsPages = settingsPages
        shortcutProvider = shortcut
        performer = perform
        settingsOpener = openSettings
        spaceSwitcher = switchSpace
        archiveReopener = reopenArchivedTab
        copier = copy
    }

    /// The commands as the palette ranks them, with the titles this device
    /// shows for them.
    var paletteCommands: [PaletteCommand] {
        BrowserPaletteCommandTitleCache.paletteCommands(for: commands, locale: .current)
    }

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        shortcutProvider(command)
    }

    func perform(_ command: ShortcutCommand) {
        performer(command)
    }

    /// Opens Settings at the page the settings call `name`; a name no page
    /// has opens nothing.
    func openSettings(_ name: String) {
        guard let destination = BrowserSettingsDestination.all.first(where: { $0.name == name }) else { return }
        settingsOpener(destination)
    }

    func switchSpace(_ id: UUID) {
        spaceSwitcher(id)
    }

    func reopenArchivedTab(_ id: UUID) {
        archiveReopener(id)
    }

    /// Copies `text` and says so in the window's notice.
    func copy(_ text: String) {
        copier(text)
    }
}

/// Caches localized command and section titles per locale so opening the
/// command palette or typing in it never repeats ~120 localization lookups.
@MainActor
private enum BrowserPaletteCommandTitleCache {
    private static var cachedLocaleIdentifier: String?
    private static var entries: [ShortcutCommand: PaletteCommand] = [:]

    static func paletteCommands(for commands: [ShortcutCommand], locale: Locale) -> [PaletteCommand] {
        if cachedLocaleIdentifier != locale.identifier {
            cachedLocaleIdentifier = locale.identifier
            entries.removeAll(keepingCapacity: true)
        }
        return commands.map { command in
            if let cached = entries[command] { return cached }
            let entry = PaletteCommand(
                command: command,
                title: command.title(locale: locale),
                sectionTitle: command.section.title(locale: locale)
            )
            entries[command] = entry
            return entry
        }
    }
}
