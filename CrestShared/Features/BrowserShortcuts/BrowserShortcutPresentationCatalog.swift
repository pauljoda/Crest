import Foundation

struct BrowserShortcutPresentationCatalog: BrowserShortcutSearchProviding {
    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func matches(
        _ command: ShortcutCommand,
        currentShortcut: BrowserShortcut?,
        query: String
    ) -> Bool {
        let searchTerms = command.searchTerms.map { BrowserShortcutLocalization.string($0, locale: locale) }
        return BrowserShortcutSearchPolicy.matches(
            query: query,
            document: BrowserShortcutSearchDocument(
                fields: [
                    command.title(locale: locale),
                    command.section.title(locale: locale),
                    searchTerms,
                    currentShortcut?.spokenDescription(locale: locale)
                        ?? BrowserShortcutLocalization.string(
                            "unassigned none no shortcut",
                            locale: locale
                        ),
                ].compactMap { $0 }
            )
        )
    }
}

enum BrowserShortcutLocalization {
    static func string(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        String(localized: Self.resource(resource, locale: locale))
    }

    static func resource(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> LocalizedStringResource {
        var localizedResource = resource
        localizedResource.locale = locale
        return localizedResource
    }

    static func list(
        _ values: [String],
        locale: Locale
    ) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values)
            ?? values.joined(separator: ", ")
    }
}

extension BrowserShortcut {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        modifiers.displayString + key.displayString(locale: locale)
    }

    func spokenDescription(locale: Locale = .current) -> String {
        [
            modifiers.spokenDescription(locale: locale),
            key.spokenDescription(locale: locale),
        ].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var spokenDescription: String {
        spokenDescription()
    }
}

extension ShortcutCommand {
    /// The title in `locale`, for text composed around it.
    func title(locale: Locale = .current) -> String {
        BrowserShortcutLocalization.string(self.title, locale: locale)
    }

    func matches(search query: String) -> Bool {
        BrowserShortcutPresentationCatalog().matches(
            self,
            currentShortcut: defaultShortcut,
            query: query
        )
    }

    func matches(
        search query: String,
        currentShortcut: BrowserShortcut?
    ) -> Bool {
        BrowserShortcutPresentationCatalog().matches(
            self,
            currentShortcut: currentShortcut,
            query: query
        )
    }
}

extension BrowserShortcutKey {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        switch self {
        case .character(let character):
            String(character).uppercased()
        case .special(let key):
            key.displayString(locale: locale)
        }
    }

    func spokenDescription(locale: Locale = .current) -> String {
        switch self {
        case .character(let character):
            String(character).lowercased()
        case .special(let key):
            key.spokenDescription(locale: locale)
        }
    }

    var spokenDescription: String {
        spokenDescription()
    }
}

extension ShortcutModifiers {
    var displayString: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    func spokenDescription(locale: Locale = .current) -> String {
        let resources: [LocalizedStringResource] = [
            contains(.control) ? "control" : nil,
            contains(.option) ? "option" : nil,
            contains(.shift) ? "shift" : nil,
            contains(.command) ? "command" : nil,
        ].compactMap { $0 }
        return resources.map { resource in
            BrowserShortcutLocalization.string(resource, locale: locale)
        }.joined(separator: " ")
    }

    var spokenDescription: String {
        spokenDescription()
    }
}

extension ShortcutSection {
    /// The title in `locale`, for text composed around it.
    func title(locale: Locale = .current) -> String {
        BrowserShortcutLocalization.string(self.title, locale: locale)
    }
}

extension BrowserShortcutSpecialKey {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        switch self {
        case .tab: "⇥"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .escape: "⎋"
        case .returnKey: "↩"
        case .delete: "⌫"
        case .forwardDelete: "⌦"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        case .space:
            BrowserShortcutLocalization.string("Space", locale: locale)
        case .f1: "F1"
        case .f2: "F2"
        case .f3: "F3"
        case .f4: "F4"
        case .f5: "F5"
        case .f6: "F6"
        case .f7: "F7"
        case .f8: "F8"
        case .f9: "F9"
        case .f10: "F10"
        case .f11: "F11"
        case .f12: "F12"
        case .f13: "F13"
        case .f14: "F14"
        case .f15: "F15"
        case .f16: "F16"
        case .f17: "F17"
        case .f18: "F18"
        case .f19: "F19"
        case .f20: "F20"
        }
    }

    func spokenDescription(locale: Locale = .current) -> String {
        guard let resource = spokenDescriptionResource else { return rawValue }
        return BrowserShortcutLocalization.string(resource, locale: locale)
    }

    var spokenDescription: String {
        spokenDescription()
    }

    private var spokenDescriptionResource: LocalizedStringResource? {
        switch self {
        case .tab: "tab"
        case .leftArrow: "left arrow"
        case .rightArrow: "right arrow"
        case .upArrow: "up arrow"
        case .downArrow: "down arrow"
        case .escape: "escape"
        case .returnKey: "return"
        case .delete: "delete"
        case .forwardDelete: "forward delete"
        case .home: "home"
        case .end: "end"
        case .pageUp: "page up"
        case .pageDown: "page down"
        case .space: "space"
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            nil
        }
    }
}

extension BrowserShortcutStore {
    func commands(matching query: String) -> [ShortcutCommand] {
        let catalog = BrowserShortcutPresentationCatalog()
        return ShortcutCommand.offered.filter {
            catalog.matches(
                $0,
                currentShortcut: shortcut(for: $0),
                query: query
            )
        }
    }
}
