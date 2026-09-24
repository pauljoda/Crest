import Foundation

/// What this process makes of the core's command catalog: which commands the
/// running engine offers, each command's default keys here, and the numbered
/// commands by position.
extension ShortcutCommand {
    // MARK: - Variables

    /// The commands this process offers anywhere a person can find one: the
    /// menu bar, the launcher and the shortcut settings list. A command whose
    /// whole feature the running engine declares absent is left out rather
    /// than shown permanently dimmed, and it cannot claim a chord either.
    static let offered = all.filter { $0.isOffered(by: BrowserEngineRegistration.current) }

    var isOfferedByCurrentEngine: Bool {
        isOffered(by: BrowserEngineRegistration.current)
    }

    /// Crest's default keys for the command on this device.
    var defaultShortcut: BrowserShortcut? {
        defaultShortcuts.first { $0.platform == .current }.map { BrowserShortcut($0.keys) }
    }

    // MARK: - Actions - Offering

    func isOffered(by registration: BrowserAdapterRegistration) -> Bool {
        requiredCapability.map(registration.supports) ?? true
    }

    // MARK: - Actions - Numbered selection

    /// The command that selects the `number`th item of `target`, counting from
    /// one. What it reaches is the core's `shortcuts.numbered_selection` rule.
    static func selecting(_ target: NumberedSelectionTarget, number: Int) -> ShortcutCommand? {
        all.first { $0.selects == target && $0.number == number }
    }
}

// MARK: - Identifiable

extension ShortcutCommand: Identifiable {
    var id: String { name }
}
