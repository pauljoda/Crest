import Foundation

struct BrowserShortcutPresentationCatalog: BrowserShortcutSearchProviding {
    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func matches(
        _ command: BrowserShortcutCommand,
        currentShortcut: BrowserShortcut?,
        query: String
    ) -> Bool {
        BrowserShortcutSearchPolicy.matches(
            query: query,
            document: BrowserShortcutSearchDocument(
                fields: [
                    BrowserShortcutLocalization.string(
                        command.titleResource,
                        locale: locale
                    ),
                    BrowserShortcutLocalization.string(
                        command.section.titleResource,
                        locale: locale
                    ),
                    BrowserShortcutLocalization.string(
                        command.relatedSearchTermsResource,
                        locale: locale
                    ),
                    currentShortcut?.spokenDescription(locale: locale)
                        ?? BrowserShortcutLocalization.string(
                            "unassigned none no shortcut",
                            locale: locale
                        ),
                ]
            )
        )
    }

    func matches(
        _ command: BrowserShortcutExtensionCommand,
        query: String
    ) -> Bool {
        BrowserShortcutSearchPolicy.containsTrimmedPhrase(
            query: query,
            fields: [
                command.extensionDisplayName,
                command.title,
                command.commandID,
                command.shortcut?.displayString(locale: locale)
                    ?? BrowserShortcutLocalization.string(
                        "unassigned",
                        locale: locale
                    ),
                command.shortcut?.spokenDescription(locale: locale)
                    ?? BrowserShortcutLocalization.string(
                        "no shortcut",
                        locale: locale
                    ),
            ]
        )
    }
}
